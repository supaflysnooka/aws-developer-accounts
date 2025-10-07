#!/bin/bash

# Terraform State Backup Script
# Creates backups of Terraform state files and stores them securely

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
BACKUP_DIR="$PROJECT_ROOT/backups/terraform-state"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

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
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    print_success "Prerequisites met"
}

create_backup_directory() {
    local backup_path="$BACKUP_DIR/$TIMESTAMP"
    mkdir -p "$backup_path"
    echo "$backup_path"
}

backup_local_state() {
    local backup_path=$1
    
    print_header "Backing Up Local State Files"
    
    # Find all terraform.tfstate files
    local state_files=$(find "$PROJECT_ROOT" -name "terraform.tfstate" -not -path "*/.*" 2>/dev/null)
    
    if [ -z "$state_files" ]; then
        print_info "No local state files found"
        return
    fi
    
    local count=0
    echo "$state_files" | while read state_file; do
        local rel_path=$(realpath --relative-to="$PROJECT_ROOT" "$state_file" 2>/dev/null || echo "$state_file")
        local backup_file="$backup_path/local/$(dirname "$rel_path")/terraform.tfstate"
        
        mkdir -p "$(dirname "$backup_file")"
        cp "$state_file" "$backup_file"
        
        # Also backup the backup file if it exists
        if [ -f "$state_file.backup" ]; then
            cp "$state_file.backup" "$backup_file.backup"
        fi
        
        print_success "Backed up: $rel_path"
        count=$((count + 1))
    done
    
    if [ $count -eq 0 ]; then
        print_info "No local state files to backup"
    fi
}

backup_remote_state() {
    local backup_path=$1
    
    print_header "Backing Up Remote State from S3"
    
    # Get S3 backend configuration
    local backend_configs=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -l "backend \"s3\"" {} \; 2>/dev/null)
    
    if [ -z "$backend_configs" ]; then
        print_info "No S3 backends configured"
        return
    fi
    
    # Extract bucket and key from backend config
    for config_file in $backend_configs; do
        local bucket=$(grep -A 10 "backend \"s3\"" "$config_file" | grep "bucket" | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d ' ')
        local key=$(grep -A 10 "backend \"s3\"" "$config_file" | grep "key" | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d ' ')
        local region=$(grep -A 10 "backend \"s3\"" "$config_file" | grep "region" | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d ' ')
        
        if [ -n "$bucket" ] && [ -n "$key" ]; then
            print_info "Backing up: s3://$bucket/$key"
            
            local backup_file="$backup_path/remote/$bucket/$key"
            mkdir -p "$(dirname "$backup_file")"
            
            if aws s3 cp "s3://$bucket/$key" "$backup_file" --region "${region:-us-west-2}" 2>/dev/null; then
                print_success "Backed up: $bucket/$key"
                
                # Also backup all versions if versioning is enabled
                local versions=$(aws s3api list-object-versions \
                    --bucket "$bucket" \
                    --prefix "$key" \
                    --query 'Versions[].[VersionId]' \
                    --output text \
                    --region "${region:-us-west-2}" 2>/dev/null | head -5)
                
                if [ -n "$versions" ]; then
                    print_info "Backing up last 5 versions..."
                    echo "$versions" | while read version_id; do
                        if [ -n "$version_id" ] && [ "$version_id" != "None" ]; then
                            aws s3api get-object \
                                --bucket "$bucket" \
                                --key "$key" \
                                --version-id "$version_id" \
                                "$backup_file.$version_id" \
                                --region "${region:-us-west-2}" &>/dev/null
                        fi
                    done
                fi
            else
                print_warning "Could not backup: $bucket/$key"
            fi
        fi
    done
}

backup_dynamodb_lock_table() {
    local backup_path=$1
    
    print_header "Backing Up DynamoDB Lock Table"
    
    # Find lock table names from backend config
    local lock_tables=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -h "dynamodb_table" {} \; | \
        sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d ' ' | sort -u)
    
    if [ -z "$lock_tables" ]; then
        print_info "No DynamoDB lock tables found"
        return
    fi
    
    for table in $lock_tables; do
        print_info "Backing up lock table: $table"
        
        # Export table items
        local table_backup="$backup_path/dynamodb/$table.json"
        mkdir -p "$(dirname "$table_backup")"
        
        aws dynamodb scan \
            --table-name "$table" \
            --output json > "$table_backup" 2>/dev/null && \
            print_success "Backed up: $table" || \
            print_warning "Could not backup: $table"
    done
}

backup_terraform_outputs() {
    local backup_path=$1
    
    print_header "Backing Up Terraform Outputs"
    
    # Find all directories with Terraform files
    local tf_dirs=$(find "$PROJECT_ROOT" -name "*.tf" -exec dirname {} \; | sort -u)
    
    for dir in $tf_dirs; do
        cd "$dir"
        
        # Skip if no state
        if ! terraform state list &>/dev/null; then
            continue
        fi
        
        local rel_path=$(realpath --relative-to="$PROJECT_ROOT" "$dir" 2>/dev/null || echo "$dir")
        local output_file="$backup_path/outputs/$rel_path/outputs.json"
        
        mkdir -p "$(dirname "$output_file")"
        
        # Export outputs
        if terraform output -json > "$output_file" 2>/dev/null; then
            print_success "Backed up outputs: $rel_path"
        fi
    done
    
    cd "$PROJECT_ROOT"
}

create_backup_manifest() {
    local backup_path=$1
    
    print_header "Creating Backup Manifest"
    
    cat > "$backup_path/MANIFEST.md" <<EOF
# Terraform State Backup

**Created**: $(date)
**User**: $(aws sts get-caller-identity --query Arn --output text)
**Git Branch**: $(git branch --show-current 2>/dev/null || echo "unknown")
**Git Commit**: $(git rev-parse HEAD 2>/dev/null || echo "unknown")

## Contents

### Local State Files
\`\`\`
$(find "$backup_path/local" -name "terraform.tfstate" 2>/dev/null | sed "s|$backup_path/||" || echo "None")
\`\`\`

### Remote State Files
\`\`\`
$(find "$backup_path/remote" -name "*.tfstate" 2>/dev/null | sed "s|$backup_path/||" || echo "None")
\`\`\`

### DynamoDB Lock Tables
\`\`\`
$(find "$backup_path/dynamodb" -name "*.json" 2>/dev/null | sed "s|$backup_path/||" || echo "None")
\`\`\`

### Terraform Outputs
\`\`\`
$(find "$backup_path/outputs" -name "outputs.json" 2>/dev/null | sed "s|$backup_path/||" || echo "None")
\`\`\`

## Backup Size

\`\`\`
$(du -sh "$backup_path" 2>/dev/null || echo "unknown")
\`\`\`

## Restoration

To restore from this backup:

1. Stop all Terraform operations
2. Copy state files to their original locations
3. Verify with: \`terraform state list\`
4. Run: \`terraform plan\` to ensure consistency

## Retention

- Keep daily backups for 7 days
- Keep weekly backups for 4 weeks
- Keep monthly backups for 12 months

---
Generated by: backup-state.sh
EOF
    
    print_success "Manifest created: $backup_path/MANIFEST.md"
}

compress_backup() {
    local backup_path=$1
    
    print_header "Compressing Backup"
    
    cd "$(dirname "$backup_path")"
    local archive_name="terraform-state-backup-$TIMESTAMP.tar.gz"
    
    tar -czf "$archive_name" "$(basename "$backup_path")" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "$archive_name" | cut -f1)
        print_success "Archive created: $archive_name ($size)"
        
        # Optionally upload to S3
        read -p "Upload archive to S3 backup bucket? (y/n): " upload
        if [ "$upload" = "y" ]; then
            read -p "S3 bucket name: " s3_bucket
            if [ -n "$s3_bucket" ]; then
                aws s3 cp "$archive_name" "s3://$s3_bucket/terraform-backups/" && \
                    print_success "Uploaded to S3: s3://$s3_bucket/terraform-backups/$archive_name"
            fi
        fi
    else
        print_error "Failed to create archive"
    fi
    
    cd "$PROJECT_ROOT"
}

cleanup_old_backups() {
    print_header "Cleaning Up Old Backups"
    
    # Keep only last 7 daily backups
    local old_backups=$(find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +7 | sort)
    
    if [ -z "$old_backups" ]; then
        print_info "No old backups to clean up"
        return
    fi
    
    print_warning "Found backups older than 7 days:"
    echo "$old_backups"
    echo ""
    
    read -p "Delete old backups? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        echo "$old_backups" | while read backup; do
            rm -rf "$backup"
            print_success "Deleted: $(basename "$backup")"
        done
    fi
}

verify_backup() {
    local backup_path=$1
    
    print_header "Verifying Backup Integrity"
    
    # Check if backup directory exists and has content
    if [ ! -d "$backup_path" ]; then
        print_error "Backup directory not found"
        return 1
    fi
    
    local file_count=$(find "$backup_path" -type f | wc -l)
    
    if [ $file_count -eq 0 ]; then
        print_error "Backup is empty"
        return 1
    fi
    
    print_success "Backup contains $file_count files"
    
    # Verify JSON files are valid
    local json_files=$(find "$backup_path" -name "*.json" 2>/dev/null)
    local invalid=0
    
    for json_file in $json_files; do
        if ! jq empty "$json_file" 2>/dev/null; then
            print_error "Invalid JSON: $json_file"
            invalid=$((invalid + 1))
        fi
    done
    
    if [ $invalid -eq 0 ]; then
        print_success "All JSON files are valid"
    else
        print_warning "$invalid invalid JSON file(s) found"
    fi
}

print_summary() {
    local backup_path=$1
    
    print_header "Backup Summary"
    
    echo ""
    echo "Backup Location: $backup_path"
    echo "Backup Time: $(date)"
    echo ""
    
    if [ -d "$backup_path" ]; then
        echo "Backup Contents:"
        echo "  Local State Files:    $(find "$backup_path/local" -name "*.tfstate" 2>/dev/null | wc -l)"
        echo "  Remote State Files:   $(find "$backup_path/remote" -name "*.tfstate" 2>/dev/null | wc -l)"
        echo "  DynamoDB Tables:      $(find "$backup_path/dynamodb" -name "*.json" 2>/dev/null | wc -l)"
        echo "  Output Files:         $(find "$backup_path/outputs" -name "*.json" 2>/dev/null | wc -l)"
        echo ""
        echo "Total Size: $(du -sh "$backup_path" | cut -f1)"
    fi
    
    echo ""
    print_success "Backup completed successfully!"
    echo ""
    print_info "To restore from this backup:"
    echo "  1. Review: $backup_path/MANIFEST.md"
    echo "  2. Copy state files to original locations"
    echo "  3. Verify: terraform state list"
}

main() {
    print_header "Terraform State Backup Tool"
    
    echo ""
    print_info "This will create a complete backup of all Terraform state"
    echo ""
    
    check_prerequisites
    
    local backup_path=$(create_backup_directory)
    print_success "Backup directory: $backup_path"
    
    # Perform backups
    backup_local_state "$backup_path"
    backup_remote_state "$backup_path"
    backup_dynamodb_lock_table "$backup_path"
    backup_terraform_outputs "$backup_path"
    
    # Create manifest and verify
    create_backup_manifest "$backup_path"
    verify_backup "$backup_path"
    
    # Optional compression
    read -p "Compress backup? (y/n): " compress
    if [ "$compress" = "y" ]; then
        compress_backup "$backup_path"
    fi
    
    # Optional cleanup
    cleanup_old_backups
    
    # Summary
    print_summary "$backup_path"
}

main "$@"
