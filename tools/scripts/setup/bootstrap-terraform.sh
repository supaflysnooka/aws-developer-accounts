#!/bin/bash

# Automated setup for AWS Developer Accounts Terraform infrastructure
# Takes care of 'chicken-and-egg' S3 backend creation situation

set -e 

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

# Configuration
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
BACKEND_CONFIG_FILE="backend-config.txt"
STATE_BUCKET_PREFIX="boseprofessional-org-terraform-state"
LOCK_TABLE_NAME="boseprofessional-org-terraform-locks"
REGION="us-west-2"

# Functions
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() {
    echo -e "${GREEN} $1${NC}"
}

print_warning() {
    echo -e "${YELLOW} $1${NC}"
}

print_error() {
    echo -e "${RED} $1${NC}"
}

print_info() {
    echo -e "${BLUE} $1${NC}"
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    local is_windows=false
    
    # Detect if running on Windows (Git Bash, WSL, etc.)
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || -n "$WINDIR" ]]; then
        is_windows=true
    fi
    
    for tool in terraform aws jq; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Install missing tools:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                terraform)
                    if [ "$is_windows" = true ]; then
                        echo "  choco install terraform  # Windows (Chocolatey)"
                        echo "  # or: winget install Hashicorp.Terraform"
                    else
                        echo "  brew install terraform  # macOS"
                    fi
                    echo "  # or visit: https://www.terraform.io/downloads"
                    ;;
                aws)
                    if [ "$is_windows" = true ]; then
                        echo "  choco install awscli  # Windows (Chocolatey)"
                        echo "  # or download MSI from: https://aws.amazon.com/cli/"
                    else
                        echo "  brew install awscli  # macOS"
                    fi
                    ;;
                jq)
                    if [ "$is_windows" = true ]; then
                        echo "  choco install jq  # Windows (Chocolatey)"
                        echo "  # or: winget install jqlang.jq"
                    else
                        echo "  brew install jq  # macOS"
                    fi
                    ;;
            esac
        done
        exit 1
    fi
    
    print_success "All required tools installed"
}

check_aws_credentials() {
    print_header "Checking AWS Credentials"
    
    # Try to get caller identity
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured or expired"
        echo ""
        echo "Please configure AWS SSO:"
        echo "  1. Run: aws configure sso"
        echo "  2. Follow the prompts to login"
        echo "  3. Set your profile: export AWS_PROFILE=<profile-name>"
        echo "  4. Run this script again"
        exit 1
    fi
    
    # Get account info
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    
    print_success "AWS credentials configured"
    print_info "Account ID: $ACCOUNT_ID"
    print_info "User: $USER_ARN"
    
    # Check if using SSO
    if [[ $USER_ARN == *"assumed-role"* ]]; then
        print_info "Using AWS SSO"
        if [ -z "$AWS_PROFILE" ]; then
            print_warning "AWS_PROFILE not set - may need to set it manually"
            echo "Current profile detection..."
            AWS_PROFILE=$(aws configure list | grep profile | awk '{print $2}')
            if [ -n "$AWS_PROFILE" ]; then
                print_info "Detected profile: $AWS_PROFILE"
            fi
        else
            print_info "Using profile: $AWS_PROFILE"
        fi
    fi
}

create_bootstrap_terraform() {
    print_header "Creating Bootstrap Terraform Configuration"
    
    local BOOTSTRAP_DIR="$PROJECT_ROOT/bootstrap/terraform-backend"
    
    # Create directory
    mkdir -p "$BOOTSTRAP_DIR"
    cd "$BOOTSTRAP_DIR"
    
    # Create main.tf
    cat > main.tf <<'EOF'
# Bootstrap Terraform configuration
# Creates S3 bucket and DynamoDB table for remote state
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # No backend - using local state for bootstrap
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "state_bucket_name" {
  description = "Name of S3 bucket for Terraform state"
  type        = string
}

variable "lock_table_name" {
  description = "Name of DynamoDB table for state locking"
  type        = string
}

# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name
  
  tags = {
    Name        = "Terraform State Storage"
    Purpose     = "terraform-backend"
    ManagedBy   = "terraform"
    Environment = "management"
  }
  
  lifecycle {
    prevent_destroy = true
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable lifecycle policy
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  rule {
    id     = "delete-old-versions"
    status = "Enabled"
    
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
  
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  
  attribute {
    name = "LockID"
    type = "S"
  }
  
  tags = {
    Name        = "Terraform State Locks"
    Purpose     = "terraform-backend"
    ManagedBy   = "terraform"
    Environment = "management"
  }
  
  lifecycle {
    prevent_destroy = true
  }
}

# Outputs
output "state_bucket_name" {
  description = "Name of the S3 bucket for state storage"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table for locking"
  value       = aws_dynamodb_table.terraform_locks.id
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.terraform_locks.arn
}

output "backend_config" {
  description = "Backend configuration for other Terraform projects"
  value = <<-EOT
    backend "s3" {
      bucket         = "${aws_s3_bucket.terraform_state.id}"
      key            = "path/to/terraform.tfstate"
      region         = "${var.region}"
      dynamodb_table = "${aws_dynamodb_table.terraform_locks.id}"
      encrypt        = true
    }
  EOT
}
EOF
    
    print_success "Bootstrap configuration created in: $BOOTSTRAP_DIR"
    cd "$PROJECT_ROOT"
}

run_bootstrap() {
    print_header "Running Bootstrap"
    
    local BOOTSTRAP_DIR="$PROJECT_ROOT/bootstrap/terraform-backend"
    cd "$BOOTSTRAP_DIR"
    
    # Check if resources already exist
    print_info "Checking if backend resources already exist..."
    
    if aws s3 ls "s3://$STATE_BUCKET_PREFIX" &> /dev/null; then
        print_warning "S3 bucket already exists: $STATE_BUCKET_PREFIX"
        print_info "Skipping bootstrap - resources already created"
        
        # Get lock table name
        if aws dynamodb describe-table --table-name "$LOCK_TABLE_NAME" &> /dev/null 2>&1; then
            print_success "DynamoDB table exists: $LOCK_TABLE_NAME"
        fi
        
        cd "$PROJECT_ROOT"
        return 0
    fi
    
    # Initialize Terraform
    print_info "Initializing Terraform..."
    terraform init
    
    # Create a tfvars file
    cat > terraform.tfvars <<EOF
region            = "$REGION"
state_bucket_name = "$STATE_BUCKET_PREFIX"
lock_table_name   = "$LOCK_TABLE_NAME"
EOF
    
    # Plan
    print_info "Planning infrastructure..."
    terraform plan -out=tfplan
    
    # Apply
    echo ""
    print_warning "About to create backend resources:"
    echo "  - S3 Bucket: $STATE_BUCKET_PREFIX"
    echo "  - DynamoDB Table: $LOCK_TABLE_NAME"
    echo ""
    read -p "Proceed with creation? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_error "Bootstrap cancelled"
        exit 1
    fi
    
    print_info "Creating backend resources..."
    terraform apply tfplan
    
    # Save backend config
    terraform output -raw backend_config > "$PROJECT_ROOT/$BACKEND_CONFIG_FILE"
    
    print_success "Backend resources created!"
    print_info "Backend configuration saved to: $BACKEND_CONFIG_FILE"
    
    cd "$PROJECT_ROOT"
}

update_main_config() {
    print_header "Updating Main Configuration"
    
    local MAIN_TF="$PROJECT_ROOT/environments/dev-accounts/main.tf"
    
    if [ ! -f "$MAIN_TF" ]; then
        print_error "Main configuration not found: $MAIN_TF"
        exit 1
    fi
    
    # Create backup
    cp "$MAIN_TF" "$MAIN_TF.backup"
    print_info "Created backup: $MAIN_TF.backup"
    
    # Check if backend is commented out
    if grep -q "^  # backend \"s3\"" "$MAIN_TF"; then
        print_info "Backend is currently commented out"
        print_info "Uncommenting backend configuration..."
        
        # Uncomment backend block
        sed -i.bak '/^  # backend "s3" {/,/^  # }/s/^  # /  /' "$MAIN_TF"
        
        # Add profile if using SSO
        if [ -n "$AWS_PROFILE" ]; then
            # Add profile line before closing brace of backend block
            sed -i.bak '/^  backend "s3" {/,/^  }/{
                /^    encrypt        = true$/a\
    profile        = "'"$AWS_PROFILE"'"
            }' "$MAIN_TF"
        fi
        
        print_success "Backend configuration updated"
    else
        print_info "Backend configuration already active"
    fi
}

migrate_to_remote_state() {
    print_header "Migrating to Remote State"
    
    cd "$PROJECT_ROOT/environments/dev-accounts"
    
    # Check if local state exists
    if [ -f "terraform.tfstate" ]; then
        print_info "Local state file found"
        print_warning "State will be migrated to S3"
    else
        print_info "No local state file - will initialize fresh"
    fi
    
    # Re-initialize with backend
    print_info "Initializing Terraform with S3 backend..."
    
    # Terraform will automatically detect state migration
    terraform init -migrate-state
    
    print_success "State migrated to S3 backend!"
    
    # Verify
    if [ -f "terraform.tfstate" ]; then
        print_info "Local state file still exists (backup)"
        print_info "You can delete it after verifying remote state works"
    fi
    
    cd "$PROJECT_ROOT"
}

print_summary() {
    print_header "Setup Complete!"
    
    echo ""
    echo -e "${GREEN}Backend Resources Created:${NC}"
    echo "  • S3 Bucket: $STATE_BUCKET_PREFIX"
    echo "  • DynamoDB Table: $LOCK_TABLE_NAME"
    echo "  • Region: $REGION"
    
    if [ -n "$AWS_PROFILE" ]; then
        echo "  • AWS Profile: $AWS_PROFILE"
    fi
    
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo "  1. Review backend configuration in: environments/dev-accounts/main.tf"
    echo "  2. Run: cd environments/dev-accounts"
    echo "  3. Run: terraform plan"
    echo "  4. Run: terraform apply"
    
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "  • Your state is now stored remotely in S3"
    echo "  • State locking prevents concurrent modifications"
    echo "  • Backup created: environments/dev-accounts/main.tf.backup"
    
    if [ -f "$PROJECT_ROOT/$BACKEND_CONFIG_FILE" ]; then
        echo ""
        echo -e "${BLUE}Backend configuration for other projects:${NC}"
        cat "$PROJECT_ROOT/$BACKEND_CONFIG_FILE"
    fi
    
    echo ""
    echo -e "${GREEN}🎉 Bootstrap complete!${NC}"
}

# Main execution
main() {
    print_header "AWS Developer Accounts - Terraform Bootstrap"
    echo ""
    echo "This script will:"
    echo "  1. Check prerequisites"
    echo "  2. Verify AWS credentials"
    echo "  3. Create S3 bucket and DynamoDB table for Terraform state"
    echo "  4. Update main configuration to use S3 backend"
    echo "  5. Migrate existing state to S3"
    echo ""
    
    check_prerequisites
    check_aws_credentials
    create_bootstrap_terraform
    run_bootstrap
    update_main_config
    migrate_to_remote_state
    print_summary
}

# Run main function
main "$@"
