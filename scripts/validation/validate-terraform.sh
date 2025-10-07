#!/bin/bash

# Terraform Validation Script
# Validates Terraform code quality, security, and best practices

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
ERRORS=0
WARNINGS=0

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; WARNINGS=$((WARNINGS + 1)); }
print_error() { echo -e "${RED}✗ $1${NC}"; ERRORS=$((ERRORS + 1)); }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

check_terraform_installed() {
    print_header "Checking Terraform Installation"
    
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform not installed"
        return 1
    fi
    
    local version=$(terraform version -json | jq -r '.terraform_version')
    print_success "Terraform $version installed"
}

validate_terraform_fmt() {
    print_header "Checking Terraform Formatting"
    
    local unformatted=$(terraform fmt -check -recursive "$PROJECT_ROOT" 2>&1 || true)
    
    if [ -n "$unformatted" ]; then
        print_error "Unformatted files found:"
        echo "$unformatted"
        print_info "Run: terraform fmt -recursive"
        return 1
    else
        print_success "All files properly formatted"
    fi
}

validate_terraform_syntax() {
    print_header "Validating Terraform Syntax"
    
    local dirs=(
        "modules"
        "environments/dev-accounts"
        "tests/unit/modules"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$PROJECT_ROOT/$dir" ]; then
            continue
        fi
        
        print_info "Validating: $dir"
        
        # Find all directories with .tf files
        while IFS= read -r -d '' tf_dir; do
            local dir_name=$(basename "$tf_dir")
            
            cd "$tf_dir"
            
            # Initialize without backend
            if ! terraform init -backend=false &> /dev/null; then
                print_error "Failed to initialize: $tf_dir"
                continue
            fi
            
            # Validate
            if ! terraform validate &> /dev/null; then
                print_error "Validation failed: $tf_dir"
                terraform validate
            else
                print_success "Valid: $dir/$dir_name"
            fi
            
            cd "$PROJECT_ROOT"
        done < <(find "$PROJECT_ROOT/$dir" -type f -name "*.tf" -exec dirname {} \; | sort -u | tr '\n' '\0')
    done
}

check_naming_conventions() {
    print_header "Checking Naming Conventions"
    
    # Check module names
    print_info "Checking module names..."
    local invalid_modules=$(find "$PROJECT_ROOT/modules" -mindepth 2 -maxdepth 2 -type d | while read dir; do
        local name=$(basename "$dir")
        if ! [[ "$name" =~ ^[a-z0-9-]+$ ]]; then
            echo "$dir"
        fi
    done)
    
    if [ -n "$invalid_modules" ]; then
        print_warning "Module names should be lowercase with hyphens:"
        echo "$invalid_modules"
    else
        print_success "Module names follow conventions"
    fi
    
    # Check variable names
    print_info "Checking variable names..."
    local invalid_vars=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -H "^variable" {} \; | while read line; do
        local var_name=$(echo "$line" | sed -n 's/.*variable "\([^"]*\)".*/\1/p')
        if ! [[ "$var_name" =~ ^[a-z][a-z0-9_]*$ ]]; then
            echo "$line"
        fi
    done)
    
    if [ -n "$invalid_vars" ]; then
        print_warning "Variable names should be snake_case:"
        echo "$invalid_vars" | head -5
    else
        print_success "Variable names follow conventions"
    fi
}

check_required_files() {
    print_header "Checking Required Files"
    
    # Check modules have required files
    find "$PROJECT_ROOT/modules" -mindepth 2 -maxdepth 2 -type d | while read module_dir; do
        local module_name=$(basename "$module_dir")
        local required_files=("main.tf" "variables.tf" "outputs.tf" "README.md")
        
        for file in "${required_files[@]}"; do
            if [ ! -f "$module_dir/$file" ]; then
                print_warning "Missing $file in module: $module_name"
            fi
        done
    done
    
    print_success "Required files check complete"
}

check_documentation() {
    print_header "Checking Documentation"
    
    # Check README files
    local modules_without_readme=$(find "$PROJECT_ROOT/modules" -mindepth 2 -maxdepth 2 -type d ! -exec test -e '{}/README.md' \; -print)
    
    if [ -n "$modules_without_readme" ]; then
        print_warning "Modules without README:"
        echo "$modules_without_readme"
    else
        print_success "All modules have README files"
    fi
    
    # Check README content
    print_info "Checking README completeness..."
    find "$PROJECT_ROOT/modules" -name "README.md" | while read readme; do
        local module_name=$(dirname "$readme" | xargs basename)
        
        # Check for key sections
        local required_sections=("Usage" "Variables" "Outputs")
        for section in "${required_sections[@]}"; do
            if ! grep -q "## $section" "$readme"; then
                print_warning "Missing ## $section in: $module_name/README.md"
            fi
        done
    done
}

check_security_best_practices() {
    print_header "Checking Security Best Practices"
    
    # Check for hardcoded secrets
    print_info "Scanning for hardcoded secrets..."
    local secrets=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -Hn -E "(password|secret|key|token)\s*=\s*\"[^$]" {} \; 2>/dev/null || true)
    
    if [ -n "$secrets" ]; then
        print_error "Potential hardcoded secrets found:"
        echo "$secrets" | head -10
        print_info "Use variables or Secrets Manager instead"
    else
        print_success "No hardcoded secrets detected"
    fi
    
    # Check for public S3 buckets
    print_info "Checking S3 bucket configurations..."
    local public_buckets=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -l "acl.*public" {} \; 2>/dev/null || true)
    
    if [ -n "$public_buckets" ]; then
        print_warning "Public S3 bucket ACLs found in:"
        echo "$public_buckets"
    else
        print_success "No public S3 buckets detected"
    fi
    
    # Check for unencrypted resources
    print_info "Checking encryption settings..."
    local unencrypted=$(find "$PROJECT_ROOT/modules" -name "*.tf" -exec grep -l "encrypted.*false" {} \; 2>/dev/null || true)
    
    if [ -n "$unencrypted" ]; then
        print_warning "Resources with encryption disabled:"
        echo "$unencrypted"
    else
        print_success "Encryption checks passed"
    fi
}

check_cost_optimization() {
    print_header "Checking Cost Optimization"
    
    # Check for cost-optimized instance types
    print_info "Checking EC2 instance types..."
    local expensive_instances=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -Hn "instance_type.*=.*\"[^t][^3-4]" {} \; 2>/dev/null | grep -v "validation" || true)
    
    if [ -n "$expensive_instances" ]; then
        print_warning "Non-optimized instance types found:"
        echo "$expensive_instances" | head -5
        print_info "Consider using t3/t4g instance types"
    else
        print_success "Instance types are cost-optimized"
    fi
    
    # Check for lifecycle policies on S3
    print_info "Checking S3 lifecycle policies..."
    find "$PROJECT_ROOT/modules/storage/s3" -name "*.tf" -exec grep -l "lifecycle_rules" {} \; &> /dev/null && \
        print_success "S3 lifecycle policies configured" || \
        print_warning "Consider adding S3 lifecycle policies"
}

check_tagging_standards() {
    print_header "Checking Tagging Standards"
    
    # Check for tags variable
    local modules_without_tags=$(find "$PROJECT_ROOT/modules" -mindepth 2 -maxdepth 2 -type d -exec sh -c '
        if [ -f "$1/variables.tf" ] && ! grep -q "variable \"tags\"" "$1/variables.tf"; then
            echo "$1"
        fi
    ' sh {} \;)
    
    if [ -n "$modules_without_tags" ]; then
        print_warning "Modules without tags variable:"
        echo "$modules_without_tags"
    else
        print_success "All modules support tagging"
    fi
    
    # Check for common_tags pattern
    print_info "Checking for common_tags pattern..."
    local modules_with_common_tags=$(find "$PROJECT_ROOT/modules" -name "main.tf" -exec grep -l "common_tags" {} \; | wc -l)
    print_success "Found $modules_with_common_tags modules using common_tags pattern"
}

check_terraform_version() {
    print_header "Checking Terraform Version Constraints"
    
    # Check for version constraints
    local files_without_version=$(find "$PROJECT_ROOT/modules" -name "main.tf" -exec sh -c '
        if ! grep -q "required_version" "$1"; then
            echo "$1"
        fi
    ' sh {} \;)
    
    if [ -n "$files_without_version" ]; then
        print_warning "Files without Terraform version constraint:"
        echo "$files_without_version"
    else
        print_success "All modules have version constraints"
    fi
    
    # Check for provider version constraints
    local files_without_provider_version=$(find "$PROJECT_ROOT/modules" -name "main.tf" -exec sh -c '
        if ! grep -q "required_providers" "$1"; then
            echo "$1"
        fi
    ' sh {} \;)
    
    if [ -n "$files_without_provider_version" ]; then
        print_warning "Files without provider version constraints:"
        echo "$files_without_provider_version"
    else
        print_success "All modules have provider version constraints"
    fi
}

run_tflint() {
    print_header "Running TFLint"
    
    if ! command -v tflint &> /dev/null; then
        print_warning "TFLint not installed - skipping"
        print_info "Install: curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash"
        return
    fi
    
    cd "$PROJECT_ROOT"
    
    # Initialize tflint
    tflint --init &> /dev/null || true
    
    # Run tflint on modules
    find modules -type f -name "*.tf" -exec dirname {} \; | sort -u | while read dir; do
        print_info "Linting: $dir"
        
        cd "$PROJECT_ROOT/$dir"
        
        if ! tflint --format compact; then
            print_error "TFLint issues found in: $dir"
        fi
    done
    
    cd "$PROJECT_ROOT"
}

run_checkov() {
    print_header "Running Checkov Security Scan"
    
    if ! command -v checkov &> /dev/null; then
        print_warning "Checkov not installed - skipping"
        print_info "Install: pip install checkov"
        return
    fi
    
    print_info "Scanning for security issues..."
    
    # Run checkov
    if checkov -d "$PROJECT_ROOT/modules" --quiet --compact 2>&1 | tee /tmp/checkov_output.txt; then
        print_success "Checkov scan passed"
    else
        local failed_checks=$(grep "Check:" /tmp/checkov_output.txt | wc -l)
        print_warning "Checkov found $failed_checks potential issues"
        print_info "Review: /tmp/checkov_output.txt"
    fi
    
    rm -f /tmp/checkov_output.txt
}

generate_report() {
    print_header "Validation Summary"
    
    echo ""
    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✓ All checks passed!${NC}"
    else
        echo -e "${YELLOW}Summary:${NC}"
        echo "  Errors: $ERRORS"
        echo "  Warnings: $WARNINGS"
        echo ""
        
        if [ $ERRORS -gt 0 ]; then
            echo -e "${RED}✗ Validation failed with $ERRORS error(s)${NC}"
            return 1
        else
            echo -e "${YELLOW}⚠ Validation completed with $WARNINGS warning(s)${NC}"
        fi
    fi
}

main() {
    print_header "Terraform Validation Suite"
    echo ""
    
    # Basic checks
    check_terraform_installed || exit 1
    
    # Code quality
    validate_terraform_fmt
    validate_terraform_syntax
    check_naming_conventions
    check_required_files
    check_documentation
    
    # Security
    check_security_best_practices
    
    # Best practices
    check_cost_optimization
    check_tagging_standards
    check_terraform_version
    
    # External tools
    run_tflint
    run_checkov
    
    # Summary
    generate_report
}

main "$@"
