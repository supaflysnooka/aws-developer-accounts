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
