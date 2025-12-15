#!/bin/bash

# Quick Account Creation Script
# Simplified wrapper around onboard-developer.sh for quick account creation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/../..")

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Quick AWS developer account creation script.

OPTIONS:
    -n, --name NAME         Developer name (required, lowercase-hyphen format)
    -e, --email EMAIL       Developer email (required)
    -b, --budget AMOUNT     Monthly budget limit in USD (default: 100)
    -j, --jira TICKET       Jira ticket ID (optional)
    -h, --help              Show this help message

EXAMPLES:
    # Create account with defaults
    $(basename "$0") -n john-smith -e john.smith@boseprofessional.com

    # Create account with custom budget
    $(basename "$0") -n jane-doe -e jane.doe@example.com -b 200 -j INFRA-123

    # Interactive mode (no arguments)
    $(basename "$0")

REQUIREMENTS:
    - AWS credentials configured (via aws configure sso)
    - Terraform installed
    - jq installed
    - Appropriate IAM permissions in AWS Organizations

EOF
}

validate_name() {
    local name=$1
    if ! [[ "$name" =~ ^[a-z0-9-]+$ ]]; then
        print_error "Developer name must contain only lowercase letters, numbers, and hyphens"
        return 1
    fi
    return 0
}

validate_email() {
    local email=$1
    if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid email format"
        return 1
    fi
    return 0
}

validate_budget() {
    local budget=$1
    if ! [[ "$budget" =~ ^[0-9]+$ ]]; then
        print_error "Budget must be a number"
        return 1
    fi
    if [ "$budget" -lt 1 ] || [ "$budget" -gt 1000 ]; then
        print_error "Budget must be between 1 and 1000 USD"
        return 1
    fi
    return 0
}

check_prerequisites() {
    local missing=()
    
    for cmd in terraform aws jq; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing[*]}"
        echo ""
        echo "Install missing tools:"
        for tool in "${missing[@]}"; do
            case $tool in
                terraform)
                    echo "  terraform: https://www.terraform.io/downloads"
                    ;;
                aws)
                    echo "  aws-cli: https://aws.amazon.com/cli/"
                    ;;
                jq)
                    echo "  jq: https://stedolan.github.io/jq/download/"
                    ;;
            esac
        done
        return 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        echo ""
        echo "Configure AWS SSO:"
        echo "  aws configure sso"
        return 1
    fi
    
    return 0
}

interactive_mode() {
    print_header "Interactive Account Creation"
    echo ""
    
    # Get developer name
    while true; do
        read -p "Developer name (lowercase-hyphen, e.g., john-smith): " dev_name
        if [ -z "$dev_name" ]; then
            print_error "Developer name is required"
            continue
        fi
        if validate_name "$dev_name"; then
            break
        fi
    done
    
    # Get email
    while true; do
        read -p "Developer email: " dev_email
        if [ -z "$dev_email" ]; then
            print_error "Email is required"
            continue
        fi
        if validate_email "$dev_email"; then
            break
        fi
    done
    
    # Get budget
    read -p "Monthly budget limit (default: 100): " budget
    budget=${budget:-100}
    if ! validate_budget "$budget"; then
        budget=100
        print_info "Using default budget: $100"
    fi
    
    # Get Jira ticket
    read -p "Jira ticket ID (optional): " jira_ticket
    
    echo ""
    print_info "Account Configuration:"
    echo "  Name:   $dev_name"
    echo "  Email:  $dev_email"
    echo "  Budget: \$$budget/month"
    [ -n "$jira_ticket" ] && echo "  Jira:   $jira_ticket"
    echo ""
    
    read -p "Create account? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_info "Cancelled"
        exit 0
    fi
    
    # Call onboard script
    call_onboard_script "$dev_name" "$dev_email" "$budget" "$jira_ticket"
}

call_onboard_script() {
    local dev_name=$1
    local dev_email=$2
    local budget=$3
    local jira_ticket=$4
    
    print_header "Creating Developer Account"
    
    local onboard_script="$SCRIPT_DIR/onboard-developer.sh"
    
    if [ ! -f "$onboard_script" ]; then
        print_error "Onboard script not found: $onboard_script"
        exit 1
    fi
    
    # Create temporary input file for non-interactive execution
    local input_file=$(mktemp)
    cat > "$input_file" <<EOF
$dev_name
$dev_email
$budget
$jira_ticket
yes
yes
EOF
    
    # Execute onboard script
    if bash "$onboard_script" < "$input_file"; then
        rm -f "$input_file"
        print_success "Account created successfully!"
        echo ""
        print_info "Next Steps:"
        echo "  1. Check generated documentation: $PROJECT_ROOT/generated/$dev_name/"
        echo "  2. Send welcome email to developer"
        echo "  3. Add developer to #aws-developer-accounts Slack"
    else
        rm -f "$input_file"
        print_error "Account creation failed"
        exit 1
    fi
}

main() {
    # Parse arguments
    local dev_name=""
    local dev_email=""
    local budget="100"
    local jira_ticket=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                dev_name="$2"
                shift 2
                ;;
            -e|--email)
                dev_email="$2"
                shift 2
                ;;
            -b|--budget)
                budget="$2"
                shift 2
                ;;
            -j|--jira)
                jira_ticket="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    # If no arguments, run interactive mode
    if [ -z "$dev_name" ] && [ -z "$dev_email" ]; then
        interactive_mode
        exit 0
    fi
    
    # Validate required arguments
    if [ -z "$dev_name" ]; then
        print_error "Developer name is required"
        show_usage
        exit 1
    fi
    
    if [ -z "$dev_email" ]; then
        print_error "Developer email is required"
        show_usage
        exit 1
    fi
    
    # Validate inputs
    if ! validate_name "$dev_name"; then
        exit 1
    fi
    
    if ! validate_email "$dev_email"; then
        exit 1
    fi
    
    if ! validate_budget "$budget"; then
        exit 1
    fi
    
    # Show configuration
    print_header "Account Creation"
    echo ""
    print_info "Configuration:"
    echo "  Name:   $dev_name"
    echo "  Email:  $dev_email"
    echo "  Budget: \$$budget/month"
    [ -n "$jira_ticket" ] && echo "  Jira:   $jira_ticket"
    echo ""
    
    # Call onboard script
    call_onboard_script "$dev_name" "$dev_email" "$budget" "$jira_ticket"
}

main "$@"
