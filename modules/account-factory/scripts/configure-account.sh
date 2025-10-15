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
