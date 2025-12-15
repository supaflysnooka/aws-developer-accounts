#!/bin/bash

# Developer Onboarding Script
# Creates a new developer account with all necessary resources

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
ENVIRONMENTS_DIR="$PROJECT_ROOT/environments/dev-accounts"
GENERATED_DIR="$PROJECT_ROOT/generated"

# Functions
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

validate_input() {
    local dev_name=$1
    local dev_email=$2
    
    # Validate name format
    if ! [[ "$dev_name" =~ ^[a-z0-9-]+$ ]]; then
        print_error "Developer name must contain only lowercase letters, numbers, and hyphens"
        exit 1
    fi
    
    # Validate email format
    if ! [[ "$dev_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid email format"
        exit 1
    fi
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    for tool in terraform aws jq; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

add_developer_to_config() {
    local dev_name=$1
    local dev_email=$2
    local budget=$3
    local jira_ticket=$4
    
    print_header "Adding Developer to Configuration"
    
    local main_tf="$ENVIRONMENTS_DIR/main.tf"
    
    # Create backup
    cp "$main_tf" "$main_tf.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Check if developer already exists
    if grep -q "\"$dev_name\"" "$main_tf"; then
        print_error "Developer $dev_name already exists in configuration"
        exit 1
    fi
    
    # Add developer to locals block
    # Find the closing brace of developers block and insert before it
    awk -v name="$dev_name" -v email="$dev_email" -v budget="$budget" -v ticket="$jira_ticket" '
    /^  }$/ && in_developers {
        printf "    \"%s\" = {\n", name
        printf "      email          = \"%s\"\n", email
        printf "      budget_limit   = %s\n", budget
        printf "      jira_ticket_id = \"%s\"\n", ticket
        printf "    }\n"
        print $0
        in_developers = 0
        next
    }
    /developers = {/ { in_developers = 1 }
    { print }
    ' "$main_tf" > "$main_tf.tmp" && mv "$main_tf.tmp" "$main_tf"
    
    print_success "Added $dev_name to main.tf"
}

terraform_plan_and_apply() {
    print_header "Running Terraform"
    
    cd "$ENVIRONMENTS_DIR"
    
    print_info "Initializing Terraform..."
    terraform init
    
    print_info "Planning changes..."
    terraform plan -out=tfplan
    
    echo ""
    print_warning "Review the plan above. Proceed with apply?"
    read -p "Continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_error "Terraform apply cancelled"
        exit 1
    fi
    
    print_info "Applying changes..."
    terraform apply tfplan
    
    print_success "Terraform apply completed"
}

generate_onboarding_docs() {
    local dev_name=$1
    
    print_header "Generating Onboarding Documentation"
    
    cd "$ENVIRONMENTS_DIR"
    
    # Get outputs
    local account_id=$(terraform output -json developer_accounts | jq -r ".\"$dev_name\".account_id")
    local state_bucket=$(terraform output -json developer_accounts | jq -r ".\"$dev_name\".state_bucket")
    local role_arn=$(terraform output -json developer_accounts | jq -r ".\"$dev_name\".role_arn")
    
    # Create generated directory
    mkdir -p "$GENERATED_DIR/$dev_name"
    
    # Generate README
    cat > "$GENERATED_DIR/$dev_name/README.md" <<EOF
# Developer Account: $dev_name

## Account Information

- **Account ID**: $account_id
- **Role ARN**: $role_arn
- **State Bucket**: $state_bucket

## Getting Started

### 1. Configure AWS CLI

\`\`\`bash
# Configure AWS profile
aws configure set profile.$dev_name role_arn $role_arn
aws configure set profile.$dev_name source_profile default
aws configure set profile.$dev_name region us-west-2

# Test access
aws sts get-caller-identity --profile $dev_name
\`\`\`

### 2. Set Environment Variable

\`\`\`bash
export AWS_PROFILE=$dev_name
\`\`\`

### 3. Initialize Your First Project

\`\`\`bash
# Clone a template or create a new directory
mkdir my-project && cd my-project

# Copy the backend configuration
cp $GENERATED_DIR/$dev_name/backend.tf .

# Initialize Terraform
terraform init
\`\`\`

## Available Modules

- **Networking**: VPC, Security Groups, ALB
- **Compute**: EC2, ECS
- **Containers**: ECR, ECS Service
- **Databases**: RDS PostgreSQL
- **Storage**: S3
- **API**: API Gateway
- **Security**: Secrets Manager

See module documentation in: \`$PROJECT_ROOT/modules/\`

## Budget & Cost Controls

- **Monthly Budget**: \$100
- **80% Alert**: Email notification at \$80
- **90% Forecast**: Proactive warning
- **100% Limit**: Resource termination may occur

Monitor your costs:
\`\`\`bash
aws ce get-cost-and-usage \\
  --time-period Start=\$(date -d '1 month ago' +%Y-%m-%d),End=\$(date +%Y-%m-%d) \\
  --granularity MONTHLY \\
  --metrics UnblendedCost \\
  --profile $dev_name
\`\`\`

## Support

- **Documentation**: [Internal Wiki](https://wiki.bose.com/aws-accounts)
- **Questions**: infrastructure-team@boseprofessional.com
- **Issues**: Create Jira ticket in INFRA project

## Next Steps

1. Review the [Developer Guide](../../docs/developer-guide/)
2. Try deploying a sample application from [Templates](../../templates/)
3. Join #aws-developer-accounts Slack channel

---
Generated on: $(date)
EOF
    
    # Generate backend.tf
    cat > "$GENERATED_DIR/$dev_name/backend.tf" <<EOF
terraform {
  backend "s3" {
    bucket         = "$state_bucket"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "bose-dev-$dev_name-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-west-2"
  
  assume_role {
    role_arn = "$role_arn"
  }
}
EOF
    
    print_success "Generated documentation in: $GENERATED_DIR/$dev_name/"
}

send_welcome_email() {
    local dev_name=$1
    local dev_email=$2
    
    print_header "Sending Welcome Email"
    
    local docs_path="$GENERATED_DIR/$dev_name/README.md"
    
    # Note: This requires AWS SES to be configured
    # For now, just display the information
    
    print_info "Welcome email content prepared"
    print_info "Send the following to $dev_email:"
    echo ""
    echo "Subject: Your AWS Developer Account is Ready!"
    echo ""
    echo "Hi,"
    echo ""
    echo "Your AWS developer account has been created!"
    echo ""
    echo "Account Name: $dev_name"
    echo "Documentation: See attached README.md"
    echo ""
    echo "Next steps:"
    echo "1. Review the documentation at: $docs_path"
    echo "2. Configure your AWS CLI profile"
    echo "3. Deploy your first application"
    echo ""
    echo "Questions? Contact infrastructure-team@boseprofessional.com"
    echo ""
    
    print_warning "Manual action required: Send welcome email to $dev_email"
}

print_summary() {
    local dev_name=$1
    
    print_header "Onboarding Complete!"
    
    echo ""
    echo -e "${GREEN}Developer account successfully created:${NC}"
    echo "  • Name: $dev_name"
    echo "  • Documentation: $GENERATED_DIR/$dev_name/"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Send welcome email to developer"
    echo "  2. Add developer to #aws-developer-accounts Slack channel"
    echo "  3. Schedule onboarding call if needed"
    echo ""
    echo -e "${GREEN}✓ Onboarding complete!${NC}"
}

main() {
    print_header "AWS Developer Account Onboarding"
    
    # Gather information
    echo ""
    read -p "Developer name (lowercase, alphanumeric, hyphens): " dev_name
    read -p "Developer email: " dev_email
    read -p "Monthly budget limit (default: 100): " budget
    budget=${budget:-100}
    read -p "Jira ticket ID: " jira_ticket
    
    echo ""
    print_info "Creating account for:"
    echo "  Name: $dev_name"
    echo "  Email: $dev_email"
    echo "  Budget: \$$budget"
    echo "  Jira: $jira_ticket"
    echo ""
    read -p "Proceed? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_error "Onboarding cancelled"
        exit 1
    fi
    
    # Execute onboarding
    validate_input "$dev_name" "$dev_email"
    check_prerequisites
    add_developer_to_config "$dev_name" "$dev_email" "$budget" "$jira_ticket"
    terraform_plan_and_apply
    generate_onboarding_docs "$dev_name"
    send_welcome_email "$dev_name" "$dev_email"
    print_summary "$dev_name"
}

main "$@"
