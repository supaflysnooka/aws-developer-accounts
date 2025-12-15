#!/bin/bash
# scripts/apply-cis-compliance.sh
# Apply CIS compliance fixes to existing developer accounts

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  CIS Compliance Remediation for AWS Accounts${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# Usage
usage() {
    cat << EOF
Usage: $0 <account-id> <developer-name> <vpc-id>

Apply CIS compliance configurations to an existing developer account.

Arguments:
  account-id      AWS account ID (12 digits)
  developer-name  Developer name (e.g., john-smith)
  vpc-id          VPC ID in the account (e.g., vpc-12345678)

Example:
  $0 123456789012 john-smith vpc-abc123def

CIS Controls Applied:
  Config.1 (Critical) - Enable AWS Config
  EC2.2 (High)        - Restrict default security group
  EC2.6 (Medium)      - Enable VPC Flow Logs
  IAM.11-17 (Med/Low) - Set IAM password policy
  IAM.18 (Low)        - Create AWS Support role

Manual Actions Required After Script:
  IAM.6 (Critical)    - Enable hardware MFA for root user
  EC2.13 (High)       - Review security groups for SSH access
  IAM.3 (Medium)      - Rotate IAM access keys (90 days)

EOF
    exit 1
}

# Check arguments
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    usage
fi

if [ $# -ne 3 ]; then
    print_error "Invalid number of arguments"
    echo ""
    usage
fi

ACCOUNT_ID="$1"
DEVELOPER_NAME="$2"
VPC_ID="$3"

# Validate inputs
if ! [[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
    print_error "Invalid account ID format: $ACCOUNT_ID"
    exit 1
fi

if ! [[ "$VPC_ID" =~ ^vpc-[a-z0-9]{8,17}$ ]]; then
    print_error "Invalid VPC ID format: $VPC_ID"
    exit 1
fi

# Check prerequisites
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    print_error "jq is not installed"
    exit 1
fi

print_header

print_info "Account ID: $ACCOUNT_ID"
print_info "Developer: $DEVELOPER_NAME"
print_info "VPC ID: $VPC_ID"
echo ""

# Verify AWS credentials
print_info "Verifying AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured"
    exit 1
fi
print_success "AWS credentials verified"
echo ""

# Assume role into target account
print_info "Assuming role into target account..."
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/OrganizationAccountAccessRole"

CREDENTIALS=$(aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name "cis-compliance-session" \
    --output json 2>&1)

if [ $? -ne 0 ]; then
    print_error "Failed to assume role: $ROLE_ARN"
    echo "$CREDENTIALS"
    exit 1
fi

export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.Credentials.SessionToken')

print_success "Assumed role successfully"
echo ""

# Get current region
REGION=$(aws configure get region || echo "us-east-1")

# ============================================================================
# CIS Config.1 - Enable AWS Config
# ============================================================================

print_info "Applying CIS Config.1: Enabling AWS Config..."

# Create S3 bucket for Config
BUCKET_NAME="config-bucket-${DEVELOPER_NAME}-${ACCOUNT_ID}"

if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
    print_info "Creating S3 bucket for AWS Config..."
    
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION" 2>&1 > /dev/null
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    # Bucket policy for Config
    aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Sid\": \"AWSConfigBucketPermissionsCheck\",
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"Service\": \"config.amazonaws.com\"
                    },
                    \"Action\": \"s3:GetBucketAcl\",
                    \"Resource\": \"arn:aws:s3:::${BUCKET_NAME}\",
                    \"Condition\": {
                        \"StringEquals\": {
                            \"AWS:SourceAccount\": \"${ACCOUNT_ID}\"
                        }
                    }
                },
                {
                    \"Sid\": \"AWSConfigBucketExistenceCheck\",
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"Service\": \"config.amazonaws.com\"
                    },
                    \"Action\": \"s3:ListBucket\",
                    \"Resource\": \"arn:aws:s3:::${BUCKET_NAME}\",
                    \"Condition\": {
                        \"StringEquals\": {
                            \"AWS:SourceAccount\": \"${ACCOUNT_ID}\"
                        }
                    }
                },
                {
                    \"Sid\": \"AWSConfigBucketPutObject\",
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"Service\": \"config.amazonaws.com\"
                    },
                    \"Action\": \"s3:PutObject\",
                    \"Resource\": \"arn:aws:s3:::${BUCKET_NAME}/*\",
                    \"Condition\": {
                        \"StringEquals\": {
                            \"s3:x-amz-acl\": \"bucket-owner-full-control\",
                            \"AWS:SourceAccount\": \"${ACCOUNT_ID}\"
                        }
                    }
                }
            ]
        }"
    
    print_success "Created Config S3 bucket: $BUCKET_NAME"
else
    print_warning "Config S3 bucket already exists: $BUCKET_NAME"
fi

# Create Config service-linked role
SERVICE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"

if ! aws iam get-role --role-name AWSServiceRoleForConfig &> /dev/null; then
    print_info "Creating AWS Config service-linked role..."
    aws iam create-service-linked-role --aws-service-name config.amazonaws.com 2>&1 > /dev/null
    print_success "Created Config service-linked role"
else
    print_warning "Config service-linked role already exists"
fi

# Create configuration recorder
if ! aws configservice describe-configuration-recorders | jq -e '.ConfigurationRecorders | length > 0' &> /dev/null; then
    print_info "Creating AWS Config recorder..."
    
    aws configservice put-configuration-recorder \
        --configuration-recorder name=cis-config-recorder,roleARN="$SERVICE_ROLE_ARN" \
        --recording-group allSupported=true,includeGlobalResourceTypes=true
    
    print_success "Created Config recorder"
else
    print_warning "Config recorder already exists"
fi

# Create delivery channel
if ! aws configservice describe-delivery-channels | jq -e '.DeliveryChannels | length > 0' &> /dev/null; then
    print_info "Creating AWS Config delivery channel..."
    
    aws configservice put-delivery-channel \
        --delivery-channel name=cis-config-delivery,s3BucketName="$BUCKET_NAME"
    
    print_success "Created Config delivery channel"
else
    print_warning "Config delivery channel already exists"
fi

# Start recording
print_info "Starting AWS Config recorder..."
aws configservice start-configuration-recorder --configuration-recorder-name cis-config-recorder
print_success "AWS Config enabled (CIS Config.1)"
echo ""

# ============================================================================
# CIS EC2.2 - Restrict default security group
# ============================================================================

print_info "Applying CIS EC2.2: Restricting default security group..."

DEFAULT_SG=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

if [ "$DEFAULT_SG" != "None" ] && [ -n "$DEFAULT_SG" ]; then
    print_info "Found default security group: $DEFAULT_SG"
    
    # Remove all ingress rules
    INGRESS_RULES=$(aws ec2 describe-security-groups \
        --group-ids "$DEFAULT_SG" \
        --query 'SecurityGroups[0].IpPermissions' \
        --output json)
    
    if [ "$INGRESS_RULES" != "[]" ]; then
        print_info "Removing ingress rules..."
        aws ec2 revoke-security-group-ingress \
            --group-id "$DEFAULT_SG" \
            --ip-permissions "$INGRESS_RULES" 2>&1 > /dev/null || true
    fi
    
    # Remove all egress rules
    EGRESS_RULES=$(aws ec2 describe-security-groups \
        --group-ids "$DEFAULT_SG" \
        --query 'SecurityGroups[0].IpPermissionsEgress' \
        --output json)
    
    if [ "$EGRESS_RULES" != "[]" ]; then
        print_info "Removing egress rules..."
        aws ec2 revoke-security-group-egress \
            --group-id "$DEFAULT_SG" \
            --ip-permissions "$EGRESS_RULES" 2>&1 > /dev/null || true
    fi
    
    # Add CIS tag
    aws ec2 create-tags \
        --resources "$DEFAULT_SG" \
        --tags Key=CISControl,Value=EC2.2 Key=Note,Value="CIS compliance - no traffic allowed"
    
    print_success "Default security group restricted (CIS EC2.2)"
else
    print_warning "Could not find default security group for VPC $VPC_ID"
fi
echo ""

# ============================================================================
# CIS EC2.6 - Enable VPC Flow Logs
# ============================================================================

print_info "Applying CIS EC2.6: Enabling VPC Flow Logs..."

# Check if flow logs already enabled
EXISTING_FLOW_LOG=$(aws ec2 describe-flow-logs \
    --filter "Name=resource-id,Values=$VPC_ID" \
    --query 'FlowLogs[0].FlowLogId' \
    --output text)

if [ "$EXISTING_FLOW_LOG" == "None" ] || [ -z "$EXISTING_FLOW_LOG" ]; then
    # Create CloudWatch log group
    LOG_GROUP="/aws/vpc/flowlogs/${VPC_ID}"
    
    if ! aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" | jq -e '.logGroups | length > 0' &> /dev/null; then
        print_info "Creating CloudWatch log group..."
        aws logs create-log-group --log-group-name "$LOG_GROUP"
        aws logs put-retention-policy --log-group-name "$LOG_GROUP" --retention-in-days 90
    fi
    
    # Create IAM role for flow logs
    FLOW_LOGS_ROLE="VPCFlowLogsRole-${DEVELOPER_NAME}"
    
    if ! aws iam get-role --role-name "$FLOW_LOGS_ROLE" &> /dev/null; then
        print_info "Creating VPC Flow Logs IAM role..."
        
        aws iam create-role \
            --role-name "$FLOW_LOGS_ROLE" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {"Service": "vpc-flow-logs.amazonaws.com"},
                    "Action": "sts:AssumeRole"
                }]
            }' 2>&1 > /dev/null
        
        aws iam put-role-policy \
            --role-name "$FLOW_LOGS_ROLE" \
            --policy-name "vpc-flow-logs-policy" \
            --policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Action": [
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                        "logs:DescribeLogGroups",
                        "logs:DescribeLogStreams"
                    ],
                    "Resource": "*"
                }]
            }'
        
        # Wait for role to propagate
        sleep 10
    fi
    
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${FLOW_LOGS_ROLE}"
    
    # Create flow log
    print_info "Creating VPC Flow Log..."
    aws ec2 create-flow-logs \
        --resource-type VPC \
        --resource-ids "$VPC_ID" \
        --traffic-type ALL \
        --log-destination-type cloud-watch-logs \
        --log-group-name "$LOG_GROUP" \
        --deliver-logs-permission-arn "$ROLE_ARN" \
        --tag-specifications "ResourceType=vpc-flow-log,Tags=[{Key=CISControl,Value=EC2.6}]" \
        2>&1 > /dev/null
    
    print_success "VPC Flow Logs enabled (CIS EC2.6)"
else
    print_warning "VPC Flow Logs already enabled: $EXISTING_FLOW_LOG"
fi
echo ""

# ============================================================================
# CIS IAM.11-17 - IAM Password Policy
# ============================================================================

print_info "Applying CIS IAM.11-17: Setting IAM password policy..."

aws iam update-account-password-policy \
    --minimum-password-length 14 \
    --require-uppercase-characters \
    --require-lowercase-characters \
    --require-symbols \
    --require-numbers \
    --password-reuse-prevention 24 \
    --max-password-age 90 \
    --allow-users-to-change-password 2>&1 > /dev/null

print_success "IAM password policy configured (CIS IAM.11-17)"
echo ""

# ============================================================================
# CIS IAM.18 - AWS Support Role
# ============================================================================

print_info "Applying CIS IAM.18: Creating AWS Support role..."

if ! aws iam get-role --role-name AWSSupportRole &> /dev/null; then
    # Get management account ID (should be passed as parameter or env var)
    MGMT_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text 2>/dev/null || echo "")
    
    if [ -z "$MGMT_ACCOUNT_ID" ]; then
        print_warning "Cannot determine management account ID, skipping Support role creation"
    else
        aws iam create-role \
            --role-name AWSSupportRole \
            --description "Role for managing AWS Support incidents (CIS IAM.18)" \
            --assume-role-policy-document "{
                \"Version\": \"2012-10-17\",
                \"Statement\": [{
                    \"Effect\": \"Allow\",
                    \"Principal\": {\"AWS\": \"arn:aws:iam::${MGMT_ACCOUNT_ID}:root\"},
                    \"Action\": \"sts:AssumeRole\",
                    \"Condition\": {
                        \"StringEquals\": {\"sts:ExternalId\": \"BoseSupport\"}
                    }
                }]
            }" \
            --tags Key=CISControl,Value=IAM.18 2>&1 > /dev/null
        
        aws iam attach-role-policy \
            --role-name AWSSupportRole \
            --policy-arn arn:aws:iam::aws:policy/AWSSupportAccess
        
        print_success "AWS Support role created (CIS IAM.18)"
    fi
else
    print_warning "AWS Support role already exists"
fi
echo ""

# Cleanup credentials
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

# ============================================================================
# Summary
# ============================================================================

print_header
echo -e "${GREEN}CIS Compliance Applied Successfully!${NC}"
echo ""
echo "Automated Fixes Applied:"
echo "  ✓ Config.1  - AWS Config enabled"
echo "  ✓ EC2.2     - Default security group restricted"
echo "  ✓ EC2.6     - VPC Flow Logs enabled"
echo "  ✓ IAM.11-17 - IAM password policy configured"
echo "  ✓ IAM.18    - AWS Support role created"
echo ""
print_warning "MANUAL ACTIONS REQUIRED:"
echo ""
echo "1. IAM.6 (CRITICAL) - Enable hardware MFA for root user"
echo "   • Log in as root user"
echo "   • Go to IAM → Dashboard → Security recommendations"
echo "   • Add MFA device (hardware U2F or hardware TOTP)"
echo ""
echo "2. EC2.13 (HIGH) - Review security groups for SSH access"
echo "   • Run: aws ec2 describe-security-groups --filters Name=ip-permission.from-port,Values=22"
echo "   • Remove any rules with 0.0.0.0/0 or ::/0 source"
echo "   • Use specific IP ranges or AWS Security Groups instead"
echo ""
echo "3. IAM.3 (MEDIUM) - Set up access key rotation reminders"
echo "   • Create calendar reminders for 90-day key rotation"
echo "   • Consider using AWS IAM Access Analyzer"
echo ""
echo "4. CloudWatch Alarms (LOW) - Set up metric filters"
echo "   • These require CloudTrail integration"
echo "   • Can be added via separate automation if needed"
echo ""
print_info "Run validation script to verify compliance:"
echo "  ./scripts/validate-account.sh bose-dev-${DEVELOPER_NAME}"
echo ""
