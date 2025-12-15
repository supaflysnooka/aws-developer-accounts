#!/bin/bash
set -e

ACCOUNT_ID="${account_id}"
DEVELOPER_NAME="${developer_name}"
MANAGEMENT_ACCOUNT_ID="${management_account_id}"
BOUNDARY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/DeveloperPermissionsBoundary"

echo "Creating DeveloperRole in account $ACCOUNT_ID with permissions boundary..."

# Assume the OrganizationAccountAccessRole to access the new account
CREDENTIALS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::$ACCOUNT_ID:role/OrganizationAccountAccessRole" \
  --role-session-name "terraform-setup" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | awk '{print $3}')

# Create trust policy
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$MANAGEMENT_ACCOUNT_ID:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "$DEVELOPER_NAME"
        }
      }
    }
  ]
}
EOF
)

# Create the role with permissions boundary attached
aws iam create-role \
  --role-name DeveloperRole \
  --assume-role-policy-document "$TRUST_POLICY" \
  --permissions-boundary "$BOUNDARY_ARN" \
  --description "Developer role for $DEVELOPER_NAME with permissions boundary" \
  --tags Key=Developer,Value=$DEVELOPER_NAME Key=ManagedBy,Value=Terraform

# Attach the same policy as the boundary to give full allowed permissions
aws iam attach-role-policy \
  --role-name DeveloperRole \
  --policy-arn "$BOUNDARY_ARN"

echo "Developer role created successfully with permissions boundary!"