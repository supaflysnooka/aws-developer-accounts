#!/bin/bash

# Environment Bootstrap Script
# Complete setup for new development environment

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
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

check_and_install_tools() {
    print_header "Checking Required Tools"
    
    local os=$(detect_os)
    local missing_tools=()
    
    # Check each required tool
    local tools=("terraform" "aws" "jq" "git")
    
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
            print_warning "$tool not installed"
        else
            local version=""
            case $tool in
                terraform)
                    version=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1)
                    ;;
                aws)
                    version=$(aws --version 2>&1 | cut -d' ' -f1)
                    ;;
                jq)
                    version=$(jq --version)
                    ;;
                git)
                    version=$(git --version | cut -d' ' -f3)
                    ;;
            esac
            print_success "$tool installed ($version)"
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo ""
        print_warning "Missing tools detected: ${missing_tools[*]}"
        echo ""
        
        read -p "Install missing tools automatically? (y/n): " install_confirm
        
        if [ "$install_confirm" = "y" ]; then
            install_missing_tools "$os" "${missing_tools[@]}"
        else
            print_error "Please install missing tools manually:"
            show_installation_instructions "$os" "${missing_tools[@]}"
            exit 1
        fi
    fi
}

install_missing_tools() {
    local os=$1
    shift
    local tools=("$@")
    
    print_header "Installing Missing Tools"
    
    case $os in
        macos)
            if ! command -v brew &> /dev/null; then
                print_error "Homebrew not installed. Install from: https://brew.sh"
                exit 1
            fi
            
            for tool in "${tools[@]}"; do
                case $tool in
                    terraform)
                        brew tap hashicorp/tap
                        brew install hashicorp/tap/terraform
                        ;;
                    aws)
                        brew install awscli
                        ;;
                    jq)
                        brew install jq
                        ;;
                    git)
                        brew install git
                        ;;
                esac
            done
            ;;
        linux)
            for tool in "${tools[@]}"; do
                case $tool in
                    terraform)
                        wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
                        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
                        sudo apt update && sudo apt install terraform
                        ;;
                    aws)
                        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                        unzip awscliv2.zip
                        sudo ./aws/install
                        rm -rf aws awscliv2.zip
                        ;;
                    jq)
                        sudo apt-get install -y jq
                        ;;
                    git)
                        sudo apt-get install -y git
                        ;;
                esac
            done
            ;;
        windows)
            print_error "Windows detected. Please use Chocolatey or install manually:"
            show_installation_instructions "$os" "${tools[@]}"
            exit 1
            ;;
    esac
    
    print_success "Tools installed successfully"
}

show_installation_instructions() {
    local os=$1
    shift
    local tools=("$@")
    
    echo ""
    case $os in
        macos)
            echo "Install via Homebrew:"
            for tool in "${tools[@]}"; do
                case $tool in
                    terraform) echo "  brew tap hashicorp/tap && brew install hashicorp/tap/terraform" ;;
                    aws) echo "  brew install awscli" ;;
                    jq) echo "  brew install jq" ;;
                    git) echo "  brew install git" ;;
                esac
            done
            ;;
        linux)
            echo "Install via package manager:"
            for tool in "${tools[@]}"; do
                case $tool in
                    terraform) echo "  Visit: https://www.terraform.io/downloads" ;;
                    aws) echo "  Visit: https://aws.amazon.com/cli/" ;;
                    jq) echo "  sudo apt-get install jq" ;;
                    git) echo "  sudo apt-get install git" ;;
                esac
            done
            ;;
        windows)
            echo "Install via Chocolatey:"
            for tool in "${tools[@]}"; do
                case $tool in
                    terraform) echo "  choco install terraform" ;;
                    aws) echo "  choco install awscli" ;;
                    jq) echo "  choco install jq" ;;
                    git) echo "  choco install git" ;;
                esac
            done
            ;;
    esac
}

configure_aws_credentials() {
    print_header "Configuring AWS Credentials"
    
    if aws sts get-caller-identity &> /dev/null; then
        print_success "AWS credentials already configured"
        local identity=$(aws sts get-caller-identity --query 'Arn' --output text)
        print_info "Current identity: $identity"
        return 0
    fi
    
    echo ""
    print_info "AWS credentials not configured"
    echo ""
    echo "Choose authentication method:"
    echo "  1) AWS SSO (recommended)"
    echo "  2) IAM User Access Keys"
    echo "  3) Skip for now"
    echo ""
    
    read -p "Select option (1-3): " auth_choice
    
    case $auth_choice in
        1)
            print_info "Starting AWS SSO configuration..."
            aws configure sso
            
            if aws sts get-caller-identity &> /dev/null; then
                print_success "AWS SSO configured successfully"
            else
                print_error "AWS SSO configuration failed"
                return 1
            fi
            ;;
        2)
            print_info "Starting IAM access key configuration..."
            aws configure
            
            if aws sts get-caller-identity &> /dev/null; then
                print_success "AWS credentials configured successfully"
            else
                print_error "AWS configuration failed"
                return 1
            fi
            ;;
        3)
            print_warning "Skipping AWS configuration"
            print_info "Configure later with: aws configure sso"
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
}

setup_project_structure() {
    print_header "Setting Up Project Structure"
    
    cd "$PROJECT_ROOT"
    
    # Create necessary directories
    local dirs=(
        "generated"
        "backups/terraform-state"
        "archive"
        "logs"
        ".terraform.d/plugin-cache"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            print_success "Created: $dir"
        else
            print_info "Exists: $dir"
        fi
    done
    
    # Create .gitignore entries if not present
    if [ -f .gitignore ]; then
        local entries=("generated/" "backups/" "*.tfstate*" ".terraform/" "*.tfvars" "*.auto.tfvars")
        for entry in "${entries[@]}"; do
            if ! grep -q "$entry" .gitignore; then
                echo "$entry" >> .gitignore
                print_success "Added to .gitignore: $entry"
            fi
        done
    fi
}

configure_terraform() {
    print_header "Configuring Terraform"
    
    # Create Terraform plugin cache directory
    mkdir -p "$HOME/.terraform.d/plugin-cache"
    
    # Create .terraformrc for plugin caching
    local terraformrc="$HOME/.terraformrc"
    if [ ! -f "$terraformrc" ]; then
        cat > "$terraformrc" <<EOF
plugin_cache_dir = "$HOME/.terraform.d/plugin-cache"
disable_checkpoint = true
EOF
        print_success "Created: $terraformrc"
    else
        print_info "Terraform config exists: $terraformrc"
    fi
    
    # Set environment variable
    export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
    
    print_success "Terraform configured"
}

run_bootstrap_terraform() {
    print_header "Bootstrapping Terraform Backend"
    
    local bootstrap_script="$SCRIPT_DIR/bootstrap-terraform.sh"
    
    if [ ! -f "$bootstrap_script" ]; then
        print_error "Bootstrap script not found: $bootstrap_script"
        return 1
    fi
    
    echo ""
    print_info "This will create S3 bucket and DynamoDB table for remote state"
    read -p "Run Terraform bootstrap? (y/n): " confirm
    
    if [ "$confirm" = "y" ]; then
        bash "$bootstrap_script"
    else
        print_warning "Skipped Terraform bootstrap"
        print_info "Run manually: ./scripts/setup/bootstrap-terraform.sh"
    fi
}

configure_git_hooks() {
    print_header "Configuring Git Hooks"
    
    local hooks_script="$SCRIPT_DIR/configure-git-hooks.sh"
    
    if [ ! -f "$hooks_script" ]; then
        print_warning "Git hooks script not found"
        return 0
    fi
    
    read -p "Configure Git pre-commit hooks? (y/n): " confirm
    
    if [ "$confirm" = "y" ]; then
        bash "$hooks_script"
    else
        print_warning "Skipped Git hooks configuration"
        print_info "Configure later: ./scripts/setup/configure-git-hooks.sh"
    fi
}

install_optional_tools() {
    print_header "Optional Tools"
    
    echo ""
    echo "Recommended optional tools:"
    echo "  • tflint - Terraform linter"
    echo "  • tfsec - Security scanner for Terraform"
    echo "  • checkov - Policy-as-code scanner"
    echo "  • pre-commit - Git hook framework"
    echo ""
    
    read -p "Install optional tools? (y/n): " confirm
    
    if [ "$confirm" != "y" ]; then
        print_info "Skipped optional tools"
        return 0
    fi
    
    local os=$(detect_os)
    
    case $os in
        macos)
            # tflint
            if ! command -v tflint &> /dev/null; then
                brew install tflint
                print_success "Installed tflint"
            fi
            
            # tfsec
            if ! command -v tfsec &> /dev/null; then
                brew install tfsec
                print_success "Installed tfsec"
            fi
            
            # pre-commit
            if ! command -v pre-commit &> /dev/null; then
                brew install pre-commit
                print_success "Installed pre-commit"
            fi
            
            # checkov
            if ! command -v checkov &> /dev/null; then
                pip3 install checkov
                print_success "Installed checkov"
            fi
            ;;
        linux)
            # tflint
            if ! command -v tflint &> /dev/null; then
                curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
                print_success "Installed tflint"
            fi
            
            # tfsec
            if ! command -v tfsec &> /dev/null; then
                curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
                print_success "Installed tfsec"
            fi
            
            # pre-commit & checkov
            if command -v pip3 &> /dev/null; then
                pip3 install pre-commit checkov
                print_success "Installed pre-commit and checkov"
            else
                print_warning "pip3 not found - skipping Python tools"
            fi
            ;;
    esac
}

create_environment_file() {
    print_header "Creating Environment Configuration"
    
    local env_file="$PROJECT_ROOT/.env.example"
    
    cat > "$env_file" <<EOF
# AWS Configuration
AWS_PROFILE=default
AWS_REGION=us-west-2

# Terraform Configuration
TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache
TF_LOG=
TF_LOG_PATH=

# Project Configuration
PROJECT_NAME=aws-developer-accounts
ENVIRONMENT=development

# Optional: Enable Terraform debug logging
# TF_LOG=DEBUG
# TF_LOG_PATH=./logs/terraform.log
EOF
    
    print_success "Created: $env_file"
    print_info "Copy to .env and customize as needed"
}

verify_installation() {
    print_header "Verifying Installation"
    
    local all_good=true
    
    # Check tools
    for tool in terraform aws jq git; do
        if command -v $tool &> /dev/null; then
            print_success "$tool is available"
        else
            print_error "$tool is not available"
            all_good=false
        fi
    done
    
    # Check AWS credentials
    if aws sts get-caller-identity &> /dev/null; then
        print_success "AWS credentials configured"
    else
        print_warning "AWS credentials not configured"
        all_good=false
    fi
    
    # Check project structure
    if [ -d "$PROJECT_ROOT/modules" ]; then
        print_success "Project structure verified"
    else
        print_error "Project structure incomplete"
        all_good=false
    fi
    
    if [ "$all_good" = true ]; then
        echo ""
        print_success "Environment setup complete!"
        return 0
    else
        echo ""
        print_warning "Environment setup completed with warnings"
        return 1
    fi
}

show_next_steps() {
    print_header "Next Steps"
    
    echo ""
    echo "Your development environment is ready! Here's what to do next:"
    echo ""
    echo "1. Review the documentation:"
    echo "   cat README.md"
    echo ""
    echo "2. Configure AWS profile (if not done):"
    echo "   aws configure sso"
    echo "   export AWS_PROFILE=your-profile-name"
    echo ""
    echo "3. Initialize Terraform:"
    echo "   cd environments/dev-accounts"
    echo "   terraform init"
    echo ""
    echo "4. Create your first developer account:"
    echo "   ./scripts/account-management/create-account.sh"
    echo ""
    echo "5. Explore available modules:"
    echo "   ls -la modules/"
    echo ""
    echo "6. Run validation:"
    echo "   ./scripts/validation/validate-terraform.sh"
    echo ""
    
    print_info "For help: cat docs/GETTING_STARTED.md"
}

main() {
    print_header "AWS Developer Accounts - Environment Bootstrap"
    
    echo ""
    print_info "This script will set up your development environment"
    echo ""
    echo "Steps:"
    echo "  1. Check and install required tools"
    echo "  2. Configure AWS credentials"
    echo "  3. Set up project structure"
    echo "  4. Configure Terraform"
    echo "  5. Bootstrap Terraform backend (optional)"
    echo "  6. Configure Git hooks (optional)"
    echo "  7. Install optional tools (optional)"
    echo ""
    
    read -p "Continue? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "Setup cancelled"
        exit 0
    fi
    
    # Run setup steps
    check_and_install_tools
    configure_aws_credentials
    setup_project_structure
    configure_terraform
    create_environment_file
    
    # Optional steps
    run_bootstrap_terraform
    configure_git_hooks
    install_optional_tools
    
    # Verify and show next steps
    verify_installation
    show_next_steps
    
    echo ""
    print_success "🎉 Bootstrap complete!"
}

main "$@"
