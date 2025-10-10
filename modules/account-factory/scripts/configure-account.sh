#!/bin/bash
# modules/account-factory/scripts/configure-account.sh
# Configure account resources using AWS CLI with assumed role

set -e

ACCOUNT_ID="${account_id}"
DEVELOPER_NAME="${developer_name}"
AWS_REGION="${aws_region}"

echo "Assuming role in account $ACCOUNT_ID..."

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::$ACCOUNT_ID:role/OrganizationAccountAccessRole \
  --role-session-name terraform-setup \
  --duration-seconds 3600 \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')

echo "Creating S3 bucket..."
if [ "$AWS_REGION" = "us-east-1" ]; then
  aws s3api create-bucket \
    --bucket bose-dev-$DEVELOPER_NAME-terraform-state \
    --region $AWS_REGION || echo "Bucket may already exist"
else
  aws s3api create-bucket \
    --bucket bose-dev-$DEVELOPER_NAME-terraform-state \
    --region $AWS_REGION \
    --create-bucket-configuration LocationConstraint=$AWS_REGION || echo "Bucket may already exist"
fi

echo "Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket bose-dev-$DEVELOPER_NAME-terraform-state \
  --versioning-configuration Status=Enabled

echo "Enabling encryption..."
aws s3api put-bucket-encryption \
  --bucket bose-dev-$DEVELOPER_NAME-terraform-state \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "Blocking public access..."
aws s3api put-public-access-block \
  --bucket bose-dev-$DEVELOPER_NAME-terraform-state \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "Creating DynamoDB table..."
aws dynamodb create-table \
  --table-name bose-dev-$DEVELOPER_NAME-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION || echo "Table may already exist"

echo "Account configuration complete!"

# ============================================================================
#!/bin/bash
# modules/account-factory/scripts/create-permission-boundary.sh
# Create IAM permission boundary policy

set -e

ACCOUNT_ID="${account_id}"
DEVELOPER_NAME="${developer_name}"

echo "Creating permission boundary policy..."

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::$ACCOUNT_ID:role/OrganizationAccountAccessRole \
  --role-session-name terraform-setup \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')

cat > /tmp/permission-boundary-$DEVELOPER_NAME.json << 'POLICY'
${policy_json}
POLICY

aws iam create-policy \
  --policy-name DeveloperPermissionBoundary \
  --policy-document file:///tmp/permission-boundary-$DEVELOPER_NAME.json \
  --description "Permission boundary for developer accounts" || echo "Policy may already exist"

rm /tmp/permission-boundary-$DEVELOPER_NAME.json

echo "Permission boundary created successfully"

# ============================================================================
#!/bin/bash
# modules/account-factory/scripts/create-developer-role.sh
# Create developer IAM role

set -e

ACCOUNT_ID="${account_id}"
DEVELOPER_NAME="${developer_name}"
MANAGEMENT_ACCOUNT_ID="${management_account_id}"

echo "Creating developer role..."

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::$ACCOUNT_ID:role/OrganizationAccountAccessRole \
  --role-session-name terraform-setup \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')

cat > /tmp/trust-policy-$DEVELOPER_NAME.json << TRUST
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$MANAGEMENT_ACCOUNT_ID:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
TRUST

aws iam create-role \
  --role-name DeveloperRole \
  --assume-role-policy-document file:///tmp/trust-policy-$DEVELOPER_NAME.json \
  --permissions-boundary arn:aws:iam::$ACCOUNT_ID:policy/DeveloperPermissionBoundary || echo "Role may already exist"

echo "Attaching PowerUserAccess policy..."
aws iam attach-role-policy \
  --role-name DeveloperRole \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess || echo "Policy may already be attached"

rm /tmp/trust-policy-$DEVELOPER_NAME.json

echo "Developer role created successfully"

# ============================================================================
#!/bin/bash
# modules/account-factory/scripts/create-budget.sh
# Create AWS budget with alerts

set -e

ACCOUNT_ID="${account_id}"
DEVELOPER_NAME="${developer_name}"
BUDGET_LIMIT="${budget_limit}"
DEVELOPER_EMAIL="${developer_email}"
ADMIN_EMAIL="${admin_email}"

echo "Creating budget..."

cat > /tmp/budget-$DEVELOPER_NAME.json << BUDGET
{
  "BudgetName": "bose-dev-$DEVELOPER_NAME-monthly-budget",
  "BudgetType": "COST",
  "TimeUnit": "MONTHLY",
  "BudgetLimit": {
    "Amount": "$BUDGET_LIMIT",
    "Unit": "USD"
  },
  "CostFilters": {
    "LinkedAccount": ["$ACCOUNT_ID"]
  }
}
BUDGET

cat > /tmp/notifications-$DEVELOPER_NAME.json << NOTIF
[
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "EMAIL",
        "Address": "$DEVELOPER_EMAIL"
      },
      {
        "SubscriptionType": "EMAIL",
        "Address": "$ADMIN_EMAIL"
      }
    ]
  },
  {
    "Notification": {
      "NotificationType": "FORECASTED",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 90,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "EMAIL",
        "Address": "$DEVELOPER_EMAIL"
      },
      {
        "SubscriptionType": "EMAIL",
        "Address": "$ADMIN_EMAIL"
      }
    ]
  }
]
NOTIF

aws budgets create-budget \
  --account-id $ACCOUNT_ID \
  --budget file:///tmp/budget-$DEVELOPER_NAME.json \
  --notifications-with-subscribers file:///tmp/notifications-$DEVELOPER_NAME.json || echo "Budget may already exist"

rm /tmp/budget-$DEVELOPER_NAME.json
rm /tmp/notifications-$DEVELOPER_NAME.json

echo "Budget created successfully"
