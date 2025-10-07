#!/bin/bash

# Install Dependencies Script
# Installs all required tools for the project

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
        if [ -f /etc/debian_version ]; then
            echo "debian"
        elif [ -f /etc/redhat-release ]; then
            echo "redhat"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

check_tool() {
    local tool=$1
    if command -v $tool &> /dev/null; then
        return 0
    else
        return 1
    fi
}

install_terraform() {
    local os=$1
    
    print_info "Installing Terraform..."
    
    case $os in
        macos)
            if check_tool brew; then
                brew tap hashicorp/tap
                brew install hashicorp/tap/terraform
            else
                print_error "Homebrew not installed. Install from: https://brew.sh"
                return 1
            fi
            ;;
        debian)
            wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
            sudo apt update && sudo apt install -y terraform
            ;;
        redhat)
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
            sudo yum -y install terraform
            ;;
        windows)
            print_error "Please install Terraform manually from: https://www.terraform.io/downloads"
            return 1
            ;;
    esac
    
    if check_tool terraform; then
        print_success "Terraform installed: $(terraform version | head -1)"
    else
        print_error "Terraform installation failed"
        return 1
    fi
}

install_aws_cli() {
    local os=$1
    
    print_info "Installing AWS CLI..."
    
    case $os in
        macos)
            if check_tool brew; then
                brew install awscli
            else
                curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
                sudo installer -pkg AWSCLIV2.pkg -target /
                rm AWSCLIV2.pkg
            fi
            ;;
        debian|redhat)
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip awscliv2.zip
            sudo ./aws/install
            rm -rf aws awscliv2.zip
            ;;
        windows)
            print_error "Please install AWS CLI manually from: https://aws.amazon.com/cli/"
            return 1
            ;;
    esac
    
    if check_tool aws; then
        print_success "AWS CLI installed: $(aws --version)"
    else
        print_error "AWS CLI installation failed"
        return 1
    fi
}

install_jq() {
    local os=$1
    
    print_info "Installing jq..."
    
    case $os in
        macos)
            if check_tool brew; then
                brew install jq
            else
                print_error "Homebrew required for jq installation"
                return 1
            fi
            ;;
        debian)
            sudo apt-get update && sudo apt-get install -y jq
            ;;
        redhat)
            sudo yum install -y jq
            ;;
        windows)
            print_error "Please install jq manually from: https://stedolan.github.io/jq/"
            return 1
            ;;
    esac
    
    if check_tool jq; then
        print_success "jq installed: $(jq --version)"
    else
        print_error "jq installation failed"
        return 1
    fi
}

install_git() {
    local os=$1
    
    print_info "Installing Git..."
    
    case $os in
        macos)
            if ! check_tool git; then
                brew install git
            fi
            ;;
        debian)
            sudo apt-get update && sudo apt-get install -y git
            ;;
        redhat)
            sudo yum install -y git
            ;;
        windows)
            print_error "Please install Git manually from: https://git-scm.com/"
            return 1
            ;;
    esac
    
    if check_tool git; then
        print_success "Git installed: $(git --version)"
    else
        print_error "Git installation failed"
        return 1
    fi
}

install_tflint() {
    local os=$1
    
    print_info "Installing tflint..."
    
    case $os in
        macos)
            if check_tool brew; then
                brew install tflint
            else
                curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
            fi
            ;;
        debian|redhat)
            curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
            ;;
        windows)
            print_warning "Please install tflint manually from: https://github.com/terraform-linters/tflint"
            return 0
            ;;
    esac
    
    if check_tool tflint; then
        print_success "tflint installed: $(tflint --version)"
    else
        print_warning "tflint installation failed (optional tool)"
    fi
}

install_tfsec() {
    local os=$1
    
    print_info "Installing tfsec..."
    
    case $os in
        macos)
            if check_tool brew; then
                brew install tfsec
            else
                curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
            fi
            ;;
        debian|redhat)
            curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
            ;;
        windows)
            print_warning "Please install tfsec manually from: https://github.com/aquasecurity/tfsec"
            return 0
            ;;
    esac
    
    if check_tool tfsec; then
        print_success "tfsec installed: $(tfsec --version)"
    else
        print_warning "tfsec installation failed (optional tool)"
    fi
}

install_checkov() {
    print_info "Installing checkov..."
    
    if check_tool pip3; then
        pip3 install checkov
        print_success "checkov installed"
    elif check_tool pip; then
        pip install checkov
        print_success "checkov installed"
    else
        print_warning "pip not found - skipping checkov (optional tool)"
    fi
}

install_pre_commit() {
    print_info "Installing pre-commit..."
    
    local os=$1
    
    case $os in
        macos)
            if check_tool brew; then
                brew install pre-commit
            elif check_tool pip3; then
                pip3 install pre-commit
            else
                print_warning "Cannot install pre-commit (optional tool)"
            fi
            ;;
        *)
            if check_tool pip3; then
                pip3 install pre-commit
            elif check_tool pip; then
                pip install pre-commit
            else
                print_warning "pip not found - skipping pre-commit (optional tool)"
            fi
            ;;
    esac
    
    if check_tool pre-commit; then
        print_success "pre-commit installed: $(pre-commit --version)"
    else
        print_warning "pre-commit installation failed (optional tool)"
    fi
}

verify_installations() {
    print_header "Verifying Installations"
    
    local all_good=true
    
    # Required tools
    local required_tools=("terraform" "aws" "jq" "git")
    for tool in "${required_tools[@]}"; do
        if check_tool $tool; then
            print_success "$tool is installed"
        else
            print_error "$tool is NOT installed"
            all_good=false
        fi
    done
    
    # Optional tools
    local optional_tools=("tflint" "tfsec" "checkov" "pre-commit")
    echo ""
    print_info "Optional tools:"
    for tool in "${optional_tools[@]}"; do
        if check_tool $tool; then
            print_success "$tool is installed"
        else
            print_warning "$tool is not installed"
        fi
    done
    
    echo ""
    if [ "$all_good" = true ]; then
        print_success "All required tools are installed!"
        return 0
    else
        print_error "Some required tools are missing"
        return 1
    fi
}

show_post_install_steps() {
    print_header "Next Steps"
    
    echo ""
    echo "Dependencies installed successfully! Next steps:"
    echo ""
    echo "1. Configure AWS credentials:"
    echo "   aws configure sso"
    echo ""
    echo "2. Verify AWS access:"
    echo "   aws sts get-caller-identity"
    echo ""
    echo "3. Bootstrap Terraform backend:"
    echo "   ./scripts/setup/bootstrap-terraform.sh"
    echo ""
    echo "4. Configure Git hooks:"
    echo "   ./scripts/setup/configure-git-hooks.sh"
    echo ""
    echo "5. Initialize Terraform:"
    echo "   cd environments/dev-accounts"
    echo "   terraform init"
    echo ""
}

main() {
    print_header "Installing Dependencies"
    
    local os=$(detect_os)
    
    echo ""
    print_info "Detected OS: $os"
    echo ""
    
    if [ "$os" = "unknown" ]; then
        print_error "Unsupported operating system"
        exit 1
    fi
    
    if [ "$os" = "windows" ]; then
        print_warning "Windows detected. Manual installation required for most tools."
        echo ""
        echo "Install via Chocolatey:"
        echo "  choco install terraform"
        echo "  choco install awscli"
        echo "  choco install jq"
        echo "  choco install git"
        exit 0
    fi
    
    echo "This will install:"
    echo "  Required:"
    echo "    • Terraform"
    echo "    • AWS CLI"
    echo "    • jq"
    echo "    • Git"
    echo "  Optional:"
    echo "    • tflint"
    echo "    • tfsec"
    echo "    • checkov"
    echo "    • pre-commit"
    echo ""
    
    read -p "Continue? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "Installation cancelled"
        exit 0
    fi
    
    # Install required tools
    check_tool terraform || install_terraform "$os"
    check_tool aws || install_aws_cli "$os"
    check_tool jq || install_jq "$os"
    check_tool git || install_git "$os"
    
    # Ask about optional tools
    echo ""
    read -p "Install optional tools (tflint, tfsec, checkov, pre-commit)? (y/n): " install_optional
    
    if [ "$install_optional" = "y" ]; then
        check_tool tflint || install_tflint "$os"
        check_tool tfsec || install_tfsec "$os"
        check_tool checkov || install_checkov
        check_tool pre-commit || install_pre_commit "$os"
    fi
    
    # Verify installations
    echo ""
    verify_installations
    
    # Show next steps
    show_post_install_steps
}

main "$@"
