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
