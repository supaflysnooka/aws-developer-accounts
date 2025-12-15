#!/bin/bash

# Key Rotation Script
# Rotates AWS access keys, Secrets Manager secrets, and SSH keys

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
ROTATION_LOG="$PROJECT_ROOT/logs/key-rotation-$(date +%Y%m%d_%H%M%S).log"

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

log_action() {
    mkdir -p "$(dirname "$ROTATION_LOG")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ROTATION_LOG"
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
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

list_iam_users_with_keys() {
    print_header "Listing IAM Users with Access Keys"
    
    local users=$(aws iam list-users --query 'Users[].UserName' --output text)
    
    echo ""
    printf "%-30s %-20s %-30s %-10s\n" "USER" "ACCESS_KEY_ID" "CREATED" "STATUS"
    echo "--------------------------------------------------------------------------------"
    
    for user in $users; do
        local keys=$(aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[].[AccessKeyId,CreateDate,Status]' --output text)
        
        if [ -n "$keys" ]; then
            while IFS=$'\t' read -r key_id create_date status; do
                # Calculate age
                local created_epoch=$(date -d "$create_date" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${create_date%+*}" +%s 2>/dev/null || echo "0")
                local now_epoch=$(date +%s)
                local age_days=$(( (now_epoch - created_epoch) / 86400 ))
                
                if [ $age_days -gt 90 ]; then
                    printf "${RED}%-30s %-20s %-30s %-10s${NC}\n" "$user" "$key_id" "$create_date ($age_days days)" "$status"
                elif [ $age_days -gt 60 ]; then
                    printf "${YELLOW}%-30s %-20s %-30s %-10s${NC}\n" "$user" "$key_id" "$create_date ($age_days days)" "$status"
                else
                    printf "%-30s %-20s %-30s %-10s\n" "$user" "$key_id" "$create_date ($age_days days)" "$status"
                fi
            done <<< "$keys"
        fi
    done
    
    echo ""
}

rotate_iam_access_key() {
    local user_name=$1
    
    print_header "Rotating Access Key for: $user_name"
    
    # List existing keys
    local existing_keys=$(aws iam list-access-keys --user-name "$user_name" --query 'AccessKeyMetadata[].AccessKeyId' --output text)
    local key_count=$(echo "$existing_keys" | wc -w)
    
    if [ $key_count -ge 2 ]; then
        print_error "User already has 2 access keys. Delete one first."
        echo "Existing keys: $existing_keys"
        return 1
    fi
    
    # Create new key
    print_info "Creating new access key..."
    local new_key=$(aws iam create-access-key --user-name "$user_name" --output json)
    
    local new_access_key_id=$(echo "$new_key" | jq -r '.AccessKey.AccessKeyId')
    local new_secret_access_key=$(echo "$new_key" | jq -r '.AccessKey.SecretAccessKey')
    
    print_success "New access key created: $new_access_key_id"
    log_action "Created new access key for $user_name: $new_access_key_id"
    
    # Save to secure location
    local key_file="$PROJECT_ROOT/backups/keys/${user_name}-keys-$(date +%Y%m%d_%H%M%S).json"
    mkdir -p "$(dirname "$key_file")"
    echo "$new_key" > "$key_file"
    chmod 600 "$key_file"
    
    print_success "New credentials saved to: $key_file"
    
    echo ""
    print_warning "IMPORTANT: Update your applications with the new credentials:"
    echo "  AWS_ACCESS_KEY_ID=$new_access_key_id"
    echo "  AWS_SECRET_ACCESS_KEY=$new_secret_access_key"
    echo ""
    
    read -p "Have you updated all applications with the new key? (yes/no): " confirmed
    
    if [ "$confirmed" != "yes" ]; then
        print_warning "Rotation paused. Resume after updating applications."
        print_info "Old key(s) remain active: $existing_keys"
        return 0
    fi
    
    # Deactivate old key(s)
    for old_key in $existing_keys; do
        print_info "Deactivating old key: $old_key"
        aws iam update-access-key --user-name "$user_name" --access-key-id "$old_key" --status Inactive
        log_action "Deactivated old key for $user_name: $old_key"
    done
    
    print_warning "Old key(s) deactivated but not deleted"
    print_info "Test your applications before deleting old keys"
    echo ""
    
    read -p "Delete old key(s) now? (yes/no): " delete_confirm
    
    if [ "$delete_confirm" = "yes" ]; then
        for old_key in $existing_keys; do
            print_info "Deleting old key: $old_key"
            aws iam delete-access-key --user-name "$user_name" --access-key-id "$old_key"
            log_action "Deleted old key for $user_name: $old_key"
        done
        print_success "Old key(s) deleted"
    else
        print_info "To delete later: aws iam delete-access-key --user-name $user_name --access-key-id <KEY_ID>"
    fi
}

list_secrets_manager_secrets() {
    print_header "Listing Secrets Manager Secrets"
    
    local secrets=$(aws secretsmanager list-secrets --query 'SecretList[].[Name,LastChangedDate,LastAccessedDate]' --output text)
    
    if [ -z "$secrets" ]; then
        print_info "No secrets found"
        return
    fi
    
    echo ""
    printf "%-50s %-30s %-30s\n" "SECRET_NAME" "LAST_CHANGED" "LAST_ACCESSED"
    echo "--------------------------------------------------------------------------------"
    
    while IFS=$'\t' read -r name last_changed last_accessed; do
        if [ -z "$last_accessed" ] || [ "$last_accessed" = "None" ]; then
            last_accessed="Never"
        fi
        
        # Calculate days since last change
        if [ -n "$last_changed" ] && [ "$last_changed" != "None" ]; then
            local changed_epoch=$(date -d "$last_changed" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${last_changed%+*}" +%s 2>/dev/null || echo "0")
            local now_epoch=$(date +%s)
            local age_days=$(( (now_epoch - changed_epoch) / 86400 ))
            
            if [ $age_days -gt 90 ]; then
                printf "${RED}%-50s %-30s %-30s${NC}\n" "$name" "$last_changed ($age_days days)" "$last_accessed"
            elif [ $age_days -gt 60 ]; then
                printf "${YELLOW}%-50s %-30s %-30s${NC}\n" "$name" "$last_changed ($age_days days)" "$last_accessed"
            else
                printf "%-50s %-30s %-30s\n" "$name" "$last_changed ($age_days days)" "$last_accessed"
            fi
        else
            printf "%-50s %-30s %-30s\n" "$name" "$last_changed" "$last_accessed"
        fi
    done <<< "$secrets"
    
    echo ""
}

rotate_secret() {
    local secret_name=$1
    
    print_header "Rotating Secret: $secret_name"
    
    # Check if rotation is enabled
    local rotation_enabled=$(aws secretsmanager describe-secret --secret-id "$secret_name" --query 'RotationEnabled' --output text)
    
    if [ "$rotation_enabled" = "True" ]; then
        print_info "Automatic rotation is enabled"
        
        read -p "Trigger rotation now? (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            aws secretsmanager rotate-secret --secret-id "$secret_name"
            print_success "Rotation triggered for: $secret_name"
            log_action "Triggered rotation for secret: $secret_name"
        fi
    else
        print_warning "Automatic rotation is NOT enabled"
        print_info "Manual rotation required"
        echo ""
        
        read -p "Update secret value manually? (y/n): " manual_confirm
        if [ "$manual_confirm" != "y" ]; then
            return 0
        fi
        
        echo ""
        print_info "Enter new secret value (or path to file):"
        read -s new_value
        
        if [ -f "$new_value" ]; then
            # Read from file
            aws secretsmanager put-secret-value \
                --secret-id "$secret_name" \
                --secret-binary fileb://"$new_value"
        else
            # Use provided value
            aws secretsmanager put-secret-value \
                --secret-id "$secret_name" \
                --secret-string "$new_value"
        fi
        
        print_success "Secret updated: $secret_name"
        log_action "Manually updated secret: $secret_name"
    fi
}

generate_ssh_key() {
    print_header "Generating New SSH Key"
    
    local key_name=$1
    local key_email=$2
    
    if [ -z "$key_name" ]; then
        read -p "Key name (e.g., deploy-key): " key_name
    fi
    
    if [ -z "$key_email" ]; then
        read -p "Email for key comment: " key_email
    fi
    
    local key_path="$HOME/.ssh/${key_name}"
    
    if [ -f "$key_path" ]; then
        print_warning "Key already exists: $key_path"
        read -p "Overwrite? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            return 0
        fi
    fi
    
    # Generate key
    ssh-keygen -t ed25519 -C "$key_email" -f "$key_path" -N ""
    
    print_success "SSH key generated: $key_path"
    print_info "Public key: $key_path.pub"
    
    # Display public key
    echo ""
    print_info "Public key content:"
    cat "$key_path.pub"
    echo ""
    
    log_action "Generated new SSH key: $key_path"
}

rotate_ec2_key_pairs() {
    print_header "EC2 Key Pairs"
    
    local key_pairs=$(aws ec2 describe-key-pairs --query 'KeyPairs[].KeyName' --output text)
    
    if [ -z "$key_pairs" ]; then
        print_info "No EC2 key pairs found"
        return
    fi
    
    print_info "Existing EC2 key pairs:"
    for key in $key_pairs; do
        echo "  • $key"
    done
    
    echo ""
    print_warning "EC2 key pair rotation requires:"
    echo "  1. Generate new key pair"
    echo "  2. Add new public key to instances"
    echo "  3. Test access with new key"
    echo "  4. Remove old key from instances"
    echo "  5. Delete old EC2 key pair"
    echo ""
    
    read -p "Create new EC2 key pair? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        return 0
    fi
    
    read -p "New key pair name: " new_key_name
    
    local output_file="$PROJECT_ROOT/backups/keys/${new_key_name}-$(date +%Y%m%d_%H%M%S).pem"
    mkdir -p "$(dirname "$output_file")"
    
    aws ec2 create-key-pair --key-name "$new_key_name" --query 'KeyMaterial' --output text > "$output_file"
    chmod 400 "$output_file"
    
    print_success "EC2 key pair created: $new_key_name"
    print_success "Private key saved: $output_file"
    log_action "Created EC2 key pair: $new_key_name"
    
    print_warning "Next steps:"
    echo "  1. Add public key to your EC2 instances"
    echo "  2. Test SSH access: ssh -i $output_file ec2-user@<instance-ip>"
    echo "  3. Update deployment scripts"
    echo "  4. Delete old key pair: aws ec2 delete-key-pair --key-name <old-key-name>"
}

interactive_menu() {
    while true; do
        print_header "Key Rotation Menu"
        
        echo ""
        echo "1) List IAM users with access keys"
        echo "2) Rotate IAM user access key"
        echo "3) List Secrets Manager secrets"
        echo "4) Rotate Secrets Manager secret"
        echo "5) Generate new SSH key"
        echo "6) Manage EC2 key pairs"
        echo "7) View rotation log"
        echo "8) Exit"
        echo ""
        
        read -p "Select option (1-8): " choice
        
        case $choice in
            1)
                list_iam_users_with_keys
                ;;
            2)
                read -p "IAM username: " username
                rotate_iam_access_key "$username"
                ;;
            3)
                list_secrets_manager_secrets
                ;;
            4)
                read -p "Secret name: " secret_name
                rotate_secret "$secret_name"
                ;;
            5)
                generate_ssh_key
                ;;
            6)
                rotate_ec2_key_pairs
                ;;
            7)
                if [ -f "$ROTATION_LOG" ]; then
                    print_header "Rotation Log"
                    cat "$ROTATION_LOG"
                else
                    print_info "No rotation log found"
                fi
                ;;
            8)
                print_info "Exiting"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

show_rotation_recommendations() {
    print_header "Key Rotation Recommendations"
    
    echo ""
    echo "Best Practices:"
    echo ""
    echo "IAM Access Keys:"
    echo "  • Rotate every 90 days"
    echo "  • Use IAM roles instead of long-lived keys when possible"
    echo "  • Monitor key usage with CloudTrail"
    echo ""
    echo "Secrets Manager:"
    echo "  • Enable automatic rotation for database passwords"
    echo "  • Rotate secrets every 30-90 days"
    echo "  • Use versioning to track changes"
    echo ""
    echo "SSH Keys:"
    echo "  • Rotate every 6-12 months"
    echo "  • Use ed25519 keys (more secure than RSA)"
    echo "  • Store private keys securely"
    echo ""
    echo "EC2 Key Pairs:"
    echo "  • Rotate annually or after team member changes"
    echo "  • Use Systems Manager Session Manager instead of SSH when possible"
    echo "  • Never commit private keys to version control"
    echo ""
}

main() {
    print_header "AWS Key Rotation Tool"
    
    check_prerequisites
    show_rotation_recommendations
    
    echo ""
    read -p "Continue to interactive menu? (y/n): " confirm
    
    if [ "$confirm" = "y" ]; then
        interactive_menu
    else
        print_info "Exiting"
        exit 0
    fi
}

main "$@"
