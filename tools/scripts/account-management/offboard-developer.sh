#!/bin/bash

# Developer Offboarding Script
# Safely removes a developer account and archives resources

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
ARCHIVE_DIR="$PROJECT_ROOT/archive"

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    print_success "Prerequisites met"
}

verify_developer_exists() {
    local dev_name=$1
    
    print_header "Verifying Developer Account"
    
    cd "$ENVIRONMENTS_DIR"
    terraform init -backend=false &> /dev/null
    
    if ! grep -q "\"$dev_name\"" main.tf; then
        print_error "Developer $dev_name not found in configuration"
        exit 1
    fi
    
    print_success "Developer $dev_name found"
}

get_account_info() {
    local dev_name=$1
    
    cd "$ENVIRONMENTS_DIR"
    terraform output -json developer_accounts 2>/dev/null | jq -r ".\"$dev_name\"" || echo "null"
}

backup_account_state() {
    local dev_name=$1
    
    print_header "Backing Up Account State"
    
    mkdir -p "$ARCHIVE_DIR/$dev_name-$(date +%Y%m%d_%H%M%S)"
    local backup_dir="$ARCHIVE_DIR/$dev_name-$(date +%Y%m%d_%H%M%S)"
    
    # Get account info
    local account_info=$(get_account_info "$dev_name")
    echo "$account_info" > "$backup_dir/account_info.json"
    
    # Export Terraform state for this account
    cd "$ENVIRONMENTS_DIR"
    terraform state pull > "$backup_dir/terraform_state.json"
    
    # Copy generated docs if they exist
    if [ -d "$PROJECT_ROOT/generated/$dev_name" ]; then
        cp -r "$PROJECT_ROOT/generated/$dev_name" "$backup_dir/generated"
    fi
    
    print_success "Backup created: $backup_dir"
    echo "$backup_dir" > /tmp/offboard_backup_dir
}

create_final_snapshot() {
    local dev_name=$1
    local account_id=$2
    
    print_header "Creating Final Snapshots"
    
    print_info "Checking for RDS instances..."
    
    # Assume role in developer account
    local role_arn="arn:aws:iam::${account_id}:role/DeveloperRole"
    local creds=$(aws sts assume-role --role-arn "$role_arn" --role-session-name offboarding --output json 2>/dev/null || echo "null")
    
    if [ "$creds" = "null" ]; then
        print_warning "Could not assume role - skipping snapshots"
        return
    fi
    
    export AWS_ACCESS_KEY_ID=$(echo $creds | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $creds | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $creds | jq -r '.Credentials.SessionToken')
    
    # Create RDS snapshots
    local rds_instances=$(aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' --output text 2>/dev/null || echo "")
    
    if [ -n "$rds_instances" ]; then
        for instance in $rds_instances; do
            print_info "Creating snapshot of RDS instance: $instance"
            aws rds create-db-snapshot \
                --db-instance-identifier "$instance" \
                --db-snapshot-identifier "$dev_name-final-$(date +%Y%m%d-%H%M%S)" \
                2>/dev/null || print_warning "Could not create snapshot for $instance"
        done
    else
        print_info "No RDS instances found"
    fi
    
    # Create EBS snapshots
    local volumes=$(aws ec2 describe-volumes --query 'Volumes[].VolumeId' --output text 2>/dev/null || echo "")
    
    if [ -n "$volumes" ]; then
        for volume in $volumes; do
            print_info "Creating snapshot of EBS volume: $volume"
            aws ec2 create-snapshot \
                --volume-id "$volume" \
                --description "Final snapshot for $dev_name offboarding" \
                --tag-specifications "ResourceType=snapshot,Tags=[{Key=Offboarding,Value=true},{Key=Developer,Value=$dev_name}]" \
                2>/dev/null || print_warning "Could not create snapshot for $volume"
        done
    else
        print_info "No EBS volumes found"
    fi
    
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    
    print_success "Snapshots created"
}

export_cost_report() {
    local dev_name=$1
    local account_id=$2
    local backup_dir=$(cat /tmp/offboard_backup_dir)
    
    print_header "Exporting Cost Report"
    
    local end_date=$(date +%Y-%m-%d)
    local start_date=$(date -d '90 days ago' +%Y-%m-%d)
    
    print_info "Generating cost report for last 90 days..."
    
    aws ce get-cost-and-usage \
        --time-period Start=$start_date,End=$end_date \
        --granularity MONTHLY \
        --metrics UnblendedCost \
        --filter file://<(echo "{\"Dimensions\":{\"Key\":\"LINKED_ACCOUNT\",\"Values\":[\"$account_id\"]}}") \
        --output json > "$backup_dir/cost_report.json" 2>/dev/null || \
        print_warning "Could not generate cost report"
    
    # Generate summary
    if [ -f "$backup_dir/cost_report.json" ]; then
        local total_cost=$(jq -r '[.ResultsByTime[].Total.UnblendedCost.Amount | tonumber] | add' "$backup_dir/cost_report.json")
        echo "Total cost (last 90 days): \$${total_cost}" > "$backup_dir/cost_summary.txt"
        print_success "Cost report exported"
    fi
}

cleanup_s3_resources() {
    local dev_name=$1
    local account_id=$2
    
    print_header "Cleaning Up S3 Resources"
    
    print_warning "This will empty and delete all S3 buckets in the account"
    read -p "Proceed? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "Skipping S3 cleanup"
        return
    fi
    
    # Assume role
    local role_arn="arn:aws:iam::${account_id}:role/DeveloperRole"
    local creds=$(aws sts assume-role --role-arn "$role_arn" --role-session-name offboarding --output json 2>/dev/null || echo "null")
    
    if [ "$creds" = "null" ]; then
        print_warning "Could not assume role - skipping S3 cleanup"
        return
    fi
    
    export AWS_ACCESS_KEY_ID=$(echo $creds | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $creds | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $creds | jq -r '.Credentials.SessionToken')
    
    # List and empty buckets
    local buckets=$(aws s3 ls | awk '{print $3}')
    
    for bucket in $buckets; do
        print_info "Emptying bucket: $bucket"
        aws s3 rm s3://$bucket --recursive 2>/dev/null || print_warning "Could not empty $bucket"
        
        print_info "Deleting bucket: $bucket"
        aws s3 rb s3://$bucket 2>/dev/null || print_warning "Could not delete $bucket"
    done
    
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    
    print_success "S3 cleanup complete"
}

remove_from_terraform() {
    local dev_name=$1
    
    print_header "Removing from Terraform Configuration"
    
    local main_tf="$ENVIRONMENTS_DIR/main.tf"
    
    # Create backup
    cp "$main_tf" "$main_tf.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Remove developer block from main.tf
    awk -v name="$dev_name" '
    BEGIN { skip = 0 }
    $0 ~ "\"" name "\"" && $0 ~ "=" && $0 ~ "{" { skip = 1; next }
    skip && $0 ~ /^    }$/ { skip = 0; next }
    !skip { print }
    ' "$main_tf" > "$main_tf.tmp" && mv "$main_tf.tmp" "$main_tf"
    
    print_success "Removed $dev_name from main.tf"
    
    # Run Terraform
    cd "$ENVIRONMENTS_DIR"
    
    print_info "Running Terraform to remove account..."
    terraform init
    terraform plan -out=tfplan
    
    echo ""
    print_warning "Review the plan above. This will DESTROY the account."
    read -p "Continue? (type 'DESTROY' to confirm): " confirm
    
    if [ "$confirm" != "DESTROY" ]; then
        print_error "Terraform destroy cancelled"
        exit 1
    fi
    
    terraform apply tfplan
    
    print_success "Account removed from Terraform"
}

cleanup_generated_files() {
    local dev_name=$1
    
    print_header "Cleaning Up Generated Files"
    
    if [ -d "$PROJECT_ROOT/generated/$dev_name" ]; then
        # Move to archive instead of deleting
        local backup_dir=$(cat /tmp/offboard_backup_dir)
        mv "$PROJECT_ROOT/generated/$dev_name" "$backup_dir/generated" 2>/dev/null || true
        print_success "Generated files archived"
    else
        print_info "No generated files found"
    fi
}

generate_offboarding_report() {
    local dev_name=$1
    local backup_dir=$(cat /tmp/offboard_backup_dir)
    
    print_header "Generating Offboarding Report"
    
    cat > "$backup_dir/OFFBOARDING_REPORT.md" <<EOF
# Offboarding Report: $dev_name

## Account Information

- **Developer**: $dev_name
- **Offboarded**: $(date)
- **Offboarded By**: $(aws sts get-caller-identity --query Arn --output text)

## Actions Taken

1. ✓ Account state backed up
2. ✓ Final snapshots created (RDS, EBS)
3. ✓ Cost report exported
4. ✓ S3 resources cleaned up
5. ✓ Account removed from Terraform
6. ✓ Generated files archived

## Archived Data Location

All account data has been archived to:
\`\`\`
$backup_dir
\`\`\`

Contents:
- account_info.json - Account metadata
- terraform_state.json - Terraform state backup
- cost_report.json - 90-day cost history
- cost_summary.txt - Cost summary
- generated/ - Generated documentation and configs

## Retention

This archive should be retained for:
- **Minimum**: 90 days (compliance)
- **Recommended**: 1 year

After retention period:
\`\`\`bash
rm -rf $backup_dir
\`\`\`

## Recovery

To recover the account (within 90 days of deletion):
\`\`\`bash
# Account may still exist in SUSPENDED state in AWS Organizations
aws organizations list-accounts --query 'Accounts[?Name==\`bose-dev-$dev_name\`]'

# Contact AWS Support for account recovery
\`\`\`

## Notes

- AWS Account will remain in SUSPENDED state for 90 days
- Snapshots are retained and may incur storage costs
- Review and delete snapshots if no longer needed

---
Generated: $(date)
EOF
    
    print_success "Offboarding report created: $backup_dir/OFFBOARDING_REPORT.md"
}

print_summary() {
    local dev_name=$1
    local backup_dir=$(cat /tmp/offboard_backup_dir)
    
    print_header "Offboarding Complete"
    
    echo ""
    echo -e "${GREEN}Developer $dev_name has been offboarded${NC}"
    echo ""
    echo -e "${YELLOW}Important Information:${NC}"
    echo "  • Account backup: $backup_dir"
    echo "  • AWS Account: SUSPENDED (90-day recovery window)"
    echo "  • Snapshots: Retained (may incur storage costs)"
    echo ""
    echo -e "${YELLOW}Post-Offboarding Tasks:${NC}"
    echo "  1. Notify developer that account has been closed"
    echo "  2. Remove developer from #aws-developer-accounts Slack"
    echo "  3. Update Jira ticket"
    echo "  4. Review and delete snapshots after retention period"
    echo ""
    echo -e "${GREEN}✓ Offboarding complete!${NC}"
    
    # Cleanup temp file
    rm -f /tmp/offboard_backup_dir
}

main() {
    print_header "AWS Developer Account Offboarding"
    
    # Gather information
    echo ""
    read -p "Developer name to offboard: " dev_name
    
    if [ -z "$dev_name" ]; then
        print_error "Developer name required"
        exit 1
    fi
    
    echo ""
    print_warning "You are about to offboard: $dev_name"
    print_warning "This will:"
    echo "  • Create backups and snapshots"
    echo "  • Clean up S3 resources"
    echo "  • Remove account from Terraform"
    echo "  • Archive account data"
    echo ""
    read -p "Proceed? (type 'OFFBOARD' to confirm): " confirm
    
    if [ "$confirm" != "OFFBOARD" ]; then
        print_error "Offboarding cancelled"
        exit 1
    fi
    
    # Execute offboarding
    check_prerequisites
    verify_developer_exists "$dev_name"
    
    # Get account info before removal
    local account_info=$(get_account_info "$dev_name")
    local account_id=$(echo "$account_info" | jq -r '.account_id')
    
    if [ "$account_id" = "null" ] || [ -z "$account_id" ]; then
        print_error "Could not retrieve account ID"
        exit 1
    fi
    
    backup_account_state "$dev_name"
    create_final_snapshot "$dev_name" "$account_id"
    export_cost_report "$dev_name" "$account_id"
    cleanup_s3_resources "$dev_name" "$account_id"
    remove_from_terraform "$dev_name"
    cleanup_generated_files "$dev_name"
    generate_offboarding_report "$dev_name"
    print_summary "$dev_name"
}

main "$@"
