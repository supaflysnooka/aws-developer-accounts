#!/bin/bash
# scripts/update-existing-acct.sh
# Update existing developer account with latest permission boundary

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 <account-id> <developer-name>

Updates an existing developer account with the latest permission boundary policy.

Arguments:
  account-id       The AWS account ID (12 digits, e.g., 123456789012)
  developer-name   The developer's name (e.g., frank-caputo)

Examples:
  $0 123456789012 frank-caputo
  $0 \$(aws organizations list-accounts --query "Accounts[?Name=='bose-dev-frank-caputo'].Id" --output text) frank-caputo

Requirements:
  - AWS CLI configured with appropriate credentials
  - Permissions to assume OrganizationAccountAccessRole
  - jq installed for JSON parsing
EOF
    exit 1
}

# Check if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# Validate number of arguments
if [ $# -ne 2 ]; then
    print_error "Incorrect number of arguments"
    echo ""
    usage
fi

ACCOUNT_ID="$1"
DEVELOPER_NAME="$2"

# Validate account ID format (12 digits)
if ! [[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
    print_error "Invalid account ID format: '$ACCOUNT_ID'"
    echo "Account ID must be exactly 12 digits"
    echo ""
    echo "Did you forget to provide the account ID?"
    echo "Find it with: aws organizations list-accounts --query \"Accounts[?Name=='bose-dev-$DEVELOPER_NAME'].Id\" --output text"
    exit 1
fi

# Validate developer name is not empty
if [ -z "$DEVELOPER_NAME" ]; then
    print_error "Developer name cannot be empty"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed or not in PATH"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    print_error "jq is not installed. Install it with: sudo apt-get install jq (Ubuntu) or brew install jq (Mac)"
    exit 1
fi

# Verify AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured or expired"
    echo "Run: aws sso login --profile <your-profile>"
    exit 1
fi

print_info "Updating account $ACCOUNT_ID for developer $DEVELOPER_NAME..."
echo ""

# Define the role ARN
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/OrganizationAccountAccessRole"
BOUNDARY_NAME="DeveloperPermissionsBoundary"
BOUNDARY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${BOUNDARY_NAME}"

print_info "Step 1: Assuming role into target account..."
echo "Role ARN: $ROLE_ARN"

# Assume role and get credentials
CREDENTIALS=$(aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name "update-boundary-session" \
    --output json 2>&1)

if [ $? -ne 0 ]; then
    print_error "Failed to assume role"
    echo "$CREDENTIALS"
    echo ""
    echo "Possible causes:"
    echo "  1. OrganizationAccountAccessRole doesn't exist in target account"
    echo "  2. You don't have permission to assume this role"
    echo "  3. Account ID is incorrect"
    exit 1
fi

# Extract credentials
export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.Credentials.SessionToken')

print_success "Successfully assumed role"
echo ""

# Define the permission boundary policy
POLICY_JSON=$(cat << 'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowedServices",
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "ec2:*",
        "lambda:*",
        "dynamodb:*",
        "rds:*",
        "cloudwatch:*",
        "logs:*",
        "sns:*",
        "sqs:*",
        "apigateway:*",
        "cloudformation:*",
        "secretsmanager:*",
        "kms:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "elasticache:*",
        "es:*",
        "kinesis:*",
        "firehose:*",
        "glue:*",
        "athena:*",
        "states:*",
        "batch:*",
        "ecs:*",
        "ecr:*",
        "eks:*",
        "comprehend:*",
        "rekognition:*",
        "textract:*",
        "translate:*",
        "polly:*",
        "transcribe:*",
        "lex:*",
        "sagemaker:*",
        "forecast:*",
        "personalize:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": [
            "us-east-1",
            "us-west-2"
          ]
        }
      }
    },
    {
      "Sid": "AllowIAMPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "lambda.amazonaws.com",
            "ec2.amazonaws.com",
            "ecs-tasks.amazonaws.com",
            "states.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "AllowIAMReadOnly",
      "Effect": "Allow",
      "Action": [
        "iam:Get*",
        "iam:List*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowLimitedIAMWrite",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:TagPolicy",
        "iam:UntagPolicy"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:PermissionsBoundary": "arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperPermissionsBoundary"
        }
      }
    },
    {
      "Sid": "DenyPermissionBoundaryRemoval",
      "Effect": "Deny",
      "Action": [
        "iam:DeleteUserPermissionsBoundary",
        "iam:DeleteRolePermissionsBoundary"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyLeavingOrganization",
      "Effect": "Deny",
      "Action": [
        "organizations:LeaveOrganization"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyRootAccess",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:root"
        }
      }
    }
  ]
}
POLICY
)

# Replace the account ID placeholder in the policy
POLICY_JSON=$(echo "$POLICY_JSON" | sed "s/\${ACCOUNT_ID}/$ACCOUNT_ID/g")

print_info "Step 2: Updating permission boundary policy..."

# Save policy to temp file
TEMP_POLICY="/tmp/permission-boundary-${ACCOUNT_ID}.json"
echo "$POLICY_JSON" > "$TEMP_POLICY"

# Check if policy already exists
POLICY_EXISTS=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$BOUNDARY_NAME'].Arn" --output text 2>&1)

if [ -z "$POLICY_EXISTS" ]; then
    # Create new policy
    print_info "Creating new permission boundary policy..."
    CREATE_RESULT=$(aws iam create-policy \
        --policy-name "$BOUNDARY_NAME" \
        --policy-document "file://$TEMP_POLICY" \
        --description "Permission boundary for developer accounts - Updated $(date +%Y-%m-%d)" \
        --output json 2>&1)
    
    if [ $? -eq 0 ]; then
        print_success "Permission boundary policy created"
    else
        print_error "Failed to create policy"
        echo "$CREATE_RESULT"
        rm -f "$TEMP_POLICY"
        exit 1
    fi
else
    # Update existing policy
    print_info "Policy exists, creating new version..."
    
    # Get current version count
    VERSION_COUNT=$(aws iam list-policy-versions \
        --policy-arn "$BOUNDARY_ARN" \
        --query 'length(Versions)' \
        --output text)
    
    # AWS allows max 5 versions, delete oldest non-default if at limit
    if [ "$VERSION_COUNT" -ge 5 ]; then
        print_warning "Reached max policy versions (5), deleting oldest..."
        OLDEST_VERSION=$(aws iam list-policy-versions \
            --policy-arn "$BOUNDARY_ARN" \
            --query 'Versions[?IsDefaultVersion==`false`] | sort_by(@, &CreateDate) | [0].VersionId' \
            --output text)
        
        aws iam delete-policy-version \
            --policy-arn "$BOUNDARY_ARN" \
            --version-id "$OLDEST_VERSION" 2>&1 > /dev/null
        
        print_success "Deleted old policy version: $OLDEST_VERSION"
    fi
    
    # Create new policy version and set as default
    UPDATE_RESULT=$(aws iam create-policy-version \
        --policy-arn "$BOUNDARY_ARN" \
        --policy-document "file://$TEMP_POLICY" \
        --set-as-default \
        --output json 2>&1)
    
    if [ $? -eq 0 ]; then
        print_success "Permission boundary policy updated"
    else
        print_error "Failed to update policy"
        echo "$UPDATE_RESULT"
        rm -f "$TEMP_POLICY"
        exit 1
    fi
fi

rm -f "$TEMP_POLICY"
echo ""

print_info "Step 3: Checking DeveloperRole permission boundary..."

# Check if DeveloperRole exists
ROLE_EXISTS=$(aws iam get-role --role-name DeveloperRole --query 'Role.RoleName' --output text 2>&1)

if [[ "$ROLE_EXISTS" == "DeveloperRole" ]]; then
    # Check if boundary is already attached
    CURRENT_BOUNDARY=$(aws iam get-role --role-name DeveloperRole --query 'Role.PermissionsBoundary.PermissionsBoundaryArn' --output text 2>&1)
    
    if [ "$CURRENT_BOUNDARY" == "$BOUNDARY_ARN" ]; then
        print_success "DeveloperRole already has correct permission boundary"
    elif [ "$CURRENT_BOUNDARY" == "None" ] || [ -z "$CURRENT_BOUNDARY" ]; then
        print_info "Attaching permission boundary to DeveloperRole..."
        aws iam put-role-permissions-boundary \
            --role-name DeveloperRole \
            --permissions-boundary "$BOUNDARY_ARN" 2>&1 > /dev/null
        
        if [ $? -eq 0 ]; then
            print_success "Permission boundary attached to DeveloperRole"
        else
            print_error "Failed to attach permission boundary to DeveloperRole"
            exit 1
        fi
    else
        print_warning "DeveloperRole has a different permission boundary: $CURRENT_BOUNDARY"
        echo "You may want to update it manually"
    fi
else
    print_warning "DeveloperRole does not exist in this account"
    echo "This is normal if the account was created without the standard DeveloperRole"
fi

echo ""
print_success "Account update completed successfully!"
echo ""
print_info "Summary:"
echo "  • Account ID: $ACCOUNT_ID"
echo "  • Developer: $DEVELOPER_NAME"
echo "  • Boundary Policy: $BOUNDARY_ARN"
echo "  • Role Status: $([ "$ROLE_EXISTS" == "DeveloperRole" ] && echo "Updated" || echo "Not found")"
echo ""

# Clean up credentials
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

print_info "Next steps:"
echo "  1. Notify the developer that their account has been updated"
echo "  2. They may need to log out and back in to get new permissions"
echo "  3. Test that the new services are accessible"
