# AWS Developer Account - Quick Start Guide

## Creating Lambda Functions

### Step 1: Create IAM Role with Permissions Boundary
```bash
# Create trust policy
cat > lambda-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Create role with boundary
aws iam create-role \
  --role-name my-lambda-execution-role \
  --assume-role-policy-document file://lambda-trust-policy.json \
  --permissions-boundary arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/DeveloperPermissionsBoundary

# Attach basic Lambda execution policy
aws iam attach-role-policy \
  --role-name my-lambda-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
```

### Step 2: Create Lambda Function
```bash
aws lambda create-function \
  --function-name my-function \
  --runtime python3.11 \
  --role arn:aws:iam::YOUR_ACCOUNT_ID:role/my-lambda-execution-role \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://function.zip
```

## Using Secrets Manager
```bash
# Create a secret
aws secretsmanager create-secret \
  --name my-app/database/credentials \
  --secret-string '{"username":"admin","password":"CHANGE_ME"}'

# Retrieve secret in your code (Python example)
import boto3
import json

client = boto3.client('secretsmanager')
response = client.get_secret_value(SecretId='my-app/database/credentials')
secret = json.loads(response['SecretString'])
```

## Creating API Gateway
```bash
# Create REST API
aws apigateway create-rest-api \
  --name my-api \
  --description "My API for testing"
```

## Common Issues

**Problem:** `AccessDenied` when creating IAM role
**Solution:** Ensure you added `--permissions-boundary` parameter

**Problem:** Lambda can't be created - "Role cannot be assumed"
**Solution:** Wait 10-30 seconds after role creation for IAM to propagate

**Problem:** Can't access service in us-east-2
**Solution:** Use allowed regions only: us-east-2 or us-east-1
