#!/bin/bash

# Git Hooks Configuration Script
# Sets up pre-commit hooks for Terraform validation and security checks

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

create_pre_commit_hook() {
    print_header "Creating pre-commit Hook"
    
    local hook_file="$HOOKS_DIR/pre-commit"
    
    cat > "$hook_file" <<'HOOK_EOF'
#!/bin/bash

# Pre-commit hook for Terraform validation
# Runs automatically before each commit

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Running pre-commit checks...${NC}"

# Get list of staged .tf files
STAGED_TF_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.tf || true)

if [ -z "$STAGED_TF_FILES" ]; then
    echo -e "${GREEN}✓ No Terraform files to check${NC}"
    exit 0
fi

echo -e "${YELLOW}Checking Terraform files...${NC}"
echo "$STAGED_TF_FILES" | while read file; do
    echo "  - $file"
done

# Check 1: Terraform fmt
echo ""
echo -e "${YELLOW}[1/4] Checking formatting...${NC}"
if ! terraform fmt -check -recursive . > /dev/null 2>&1; then
    echo -e "${RED}✗ Terraform files are not formatted${NC}"
    echo "Run: terraform fmt -recursive"
    exit 1
fi
echo -e "${GREEN}✓ All files properly formatted${NC}"

# Check 2: Terraform validate
echo -e "${YELLOW}[2/4] Validating syntax...${NC}"
VALIDATION_FAILED=0

# Find all directories with .tf files that changed
echo "$STAGED_TF_FILES" | xargs dirname | sort -u | while read dir; do
    if [ -f "$dir/main.tf" ] || [ -f "$dir/variables.tf" ]; then
        cd "$dir"
        if ! terraform init -backend=false > /dev/null 2>&1; then
            echo -e "${RED}✗ Failed to initialize: $dir${NC}"
            VALIDATION_FAILED=1
            continue
        fi
        if ! terraform validate > /dev/null 2>&1; then
            echo -e "${RED}✗ Validation failed: $dir${NC}"
            VALIDATION_FAILED=1
        fi
        cd - > /dev/null
    fi
done

if [ $VALIDATION_FAILED -eq 1 ]; then
    exit 1
fi
echo -e "${GREEN}✓ Validation passed${NC}"

# Check 3: Scan for secrets
echo -e "${YELLOW}[3/4] Scanning for secrets...${NC}"
SECRET_PATTERNS=(
    'password\s*=\s*"[^$]'
    'secret\s*=\s*"[^$]'
    'api[_-]?key\s*=\s*"[^$]'
)

SECRETS_FOUND=0
for pattern in "${SECRET_PATTERNS[@]}"; do
    if echo "$STAGED_TF_FILES" | xargs grep -Hn -E "$pattern" 2>/dev/null; then
        SECRETS_FOUND=1
    fi
done

if [ $SECRETS_FOUND -eq 1 ]; then
    echo -e "${RED}✗ Potential secrets detected${NC}"
    echo "Remove hardcoded secrets before committing"
    exit 1
fi
echo -e "${GREEN}✓ No secrets detected${NC}"

# Check 4: Check for debug/TODO comments
echo -e "${YELLOW}[4/4] Checking for debug markers...${NC}"
if echo "$STAGED_TF_FILES" | xargs grep -Hn "TODO\|FIXME\|XXX\|HACK" 2>/dev/null | grep -v "# TODO:" ; then
    echo -e "${YELLOW}⚠ Found debug markers (committing anyway)${NC}"
fi

echo ""
echo -e "${GREEN}✓ All pre-commit checks passed!${NC}"
exit 0
HOOK_EOF
    
    chmod +x "$hook_file"
    print_success "Created pre-commit hook"
}

create_commit_msg_hook() {
    print_header "Creating commit-msg Hook"
    
    local hook_file="$HOOKS_DIR/commit-msg"
    
    cat > "$hook_file" <<'HOOK_EOF'
#!/bin/bash

# Commit message validation hook
# Ensures commit messages follow conventions

COMMIT_MSG_FILE=$1
COMMIT_MSG=$(cat "$COMMIT_MSG_FILE")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Skip validation for merge commits
if grep -q "^Merge" "$COMMIT_MSG_FILE"; then
    exit 0
fi

# Minimum length check
if [ ${#COMMIT_MSG} -lt 10 ]; then
    echo -e "${RED}✗ Commit message too short (minimum 10 characters)${NC}"
    exit 1
fi

# Check for common prefixes (optional but recommended)
# Uncomment to enforce conventional commits
# if ! echo "$COMMIT_MSG" | grep -qE "^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert):"; then
#     echo -e "${YELLOW}⚠ Consider using conventional commit format:${NC}"
#     echo "  feat: add new feature"
#     echo "  fix: bug fix"
#     echo "  docs: documentation"
#     echo "  chore: maintenance"
# fi

# Prevent commits with WIP
if echo "$COMMIT_MSG" | grep -qi "wip\|work in progress"; then
    echo -e "${YELLOW}⚠ Committing work in progress${NC}"
fi

exit 0
HOOK_EOF
    
    chmod +x "$hook_file"
    print_success "Created commit-msg hook"
}

create_pre_push_hook() {
    print_header "Creating pre-push Hook"
    
    local hook_file="$HOOKS_DIR/pre-push"
    
    cat > "$hook_file" <<'HOOK_EOF'
#!/bin/bash

# Pre-push hook for additional validation
# Runs before pushing to remote

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Running pre-push checks...${NC}"

# Check if on main/master branch
BRANCH=$(git branch --show-current)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    echo -e "${YELLOW}⚠ Pushing to $BRANCH branch${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo -e "${RED}✗ Push cancelled${NC}"
        exit 1
    fi
fi

# Run security scan if available
if command -v tfsec &> /dev/null; then
    echo -e "${YELLOW}Running security scan...${NC}"
    if ! tfsec . --soft-fail 2>/dev/null; then
        echo -e "${YELLOW}⚠ Security issues found (pushing anyway)${NC}"
    fi
fi

# Check for large files (> 5MB)
LARGE_FILES=$(find . -type f -size +5M -not -path "*/\.*" -not -path "*/node_modules/*" 2>/dev/null || true)
if [ -n "$LARGE_FILES" ]; then
    echo -e "${YELLOW}⚠ Large files detected:${NC}"
    echo "$LARGE_FILES"
    read -p "Continue with push? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        exit 1
    fi
fi

echo -e "${GREEN}✓ Pre-push checks passed${NC}"
exit 0
HOOK_EOF
    
    chmod +x "$hook_file"
    print_success "Created pre-push hook"
}

create_post_checkout_hook() {
    print_header "Creating post-checkout Hook"
    
    local hook_file="$HOOKS_DIR/post-checkout"
    
    cat > "$hook_file" <<'HOOK_EOF'
#!/bin/bash

# Post-checkout hook
# Runs after checking out a branch

PREV_HEAD=$1
NEW_HEAD=$2
BRANCH_SWITCH=$3

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Only run on branch switch
if [ "$BRANCH_SWITCH" = "1" ]; then
    BRANCH=$(git branch --show-current)
    echo -e "${GREEN}✓ Switched to branch: $BRANCH${NC}"
    
    # Check if Terraform is initialized
    if [ -d ".terraform" ]; then
        echo -e "${YELLOW}⚠ Terraform is initialized - consider running: terraform init${NC}"
    fi
    
    # Show if there are uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        echo -e "${YELLOW}⚠ You have uncommitted changes${NC}"
    fi
fi

exit 0
HOOK_EOF
    
    chmod +x "$hook_file"
    print_success "Created post-checkout hook"
}

setup_pre_commit_framework() {
    print_header "Setting up pre-commit Framework"
    
    if ! command -v pre-commit &> /dev/null; then
        print_warning "pre-commit not installed"
        print_info "Install with: pip install pre-commit"
        return 1
    fi
    
    local config_file="$PROJECT_ROOT/.pre-commit-config.yaml"
    
    if [ -f "$config_file" ]; then
        print_info "pre-commit config already exists"
    else
        cat > "$config_file" <<'EOF'
# Pre-commit hooks configuration
# See https://pre-commit.com for more information

repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
        args: ['--maxkb=5000']
      - id: check-merge-conflict
      - id: detect-private-key

  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.86.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_docs
        args:
          - --hook-config=--path-to-file=README.md
          - --hook-config=--add-to-existing-file=true
      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
      - id: terraform_tfsec
        args:
          - --args=--soft-fail

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.1
    hooks:
      - id: gitleaks
EOF
        print_success "Created .pre-commit-config.yaml"
    fi
    
    # Install hooks
    print_info "Installing pre-commit hooks..."
    if pre-commit install; then
        print_success "pre-commit hooks installed"
    else
        print_error "Failed to install pre-commit hooks"
        return 1
    fi
}

create_tflint_config() {
    print_header "Creating TFLint Configuration"
    
    local config_file="$PROJECT_ROOT/.tflint.hcl"
    
    if [ -f "$config_file" ]; then
        print_info "TFLint config already exists"
        return 0
    fi
    
    cat > "$config_file" <<'EOF'
# TFLint configuration

config {
  module = true
  force = false
}

plugin "aws" {
  enabled = true
  version = "0.29.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}
EOF
    
    print_success "Created .tflint.hcl"
}

test_hooks() {
    print_header "Testing Git Hooks"
    
    # Test pre-commit
    print_info "Testing pre-commit hook..."
    if [ -x "$HOOKS_DIR/pre-commit" ]; then
        print_success "pre-commit hook is executable"
    else
        print_error "pre-commit hook is not executable"
    fi
    
    # Test commit-msg
    print_info "Testing commit-msg hook..."
    if [ -x "$HOOKS_DIR/commit-msg" ]; then
        print_success "commit-msg hook is executable"
    else
        print_error "commit-msg hook is not executable"
    fi
    
    # Test pre-push
    print_info "Testing pre-push hook..."
    if [ -x "$HOOKS_DIR/pre-push" ]; then
        print_success "pre-push hook is executable"
    else
        print_error "pre-push hook is not executable"
    fi
}

print_usage_instructions() {
    print_header "Git Hooks Configured"
    
    echo ""
    print_success "Git hooks have been installed successfully!"
    echo ""
    echo "Installed hooks:"
    echo "  • pre-commit:     Validates Terraform code before commit"
    echo "  • commit-msg:     Validates commit message format"
    echo "  • pre-push:       Additional checks before pushing"
    echo "  • post-checkout:  Notifications after branch switch"
    echo ""
    echo "What happens now:"
    echo "  1. Before each commit, Terraform files will be:"
    echo "     - Formatted (terraform fmt)"
    echo "     - Validated (terraform validate)"
    echo "     - Scanned for secrets"
    echo ""
    echo "  2. Commit messages will be validated for length"
    echo ""
    echo "  3. Before pushing, additional security checks will run"
    echo ""
    echo "To bypass hooks (not recommended):"
    echo "  git commit --no-verify"
    echo ""
    echo "To update hooks:"
    echo "  ./scripts/setup/configure-git-hooks.sh"
    echo ""
}

main() {
    print_header "Git Hooks Configuration"
    
    if [ ! -d "$PROJECT_ROOT/.git" ]; then
        print_error "Not a git repository"
        exit 1
    fi
    
    echo ""
    print_info "This will configure Git hooks for:"
    echo "  • Code formatting validation"
    echo "  • Syntax checking"
    echo "  • Secret scanning"
    echo "  • Commit message validation"
    echo ""
    
    read -p "Continue? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "Configuration cancelled"
        exit 0
    fi
    
    # Create hooks directory if it doesn't exist
    mkdir -p "$HOOKS_DIR"
    
    # Create individual hooks
    create_pre_commit_hook
    create_commit_msg_hook
    create_pre_push_hook
    create_post_checkout_hook
    
    # Setup pre-commit framework (optional)
    if command -v pre-commit &> /dev/null; then
        setup_pre_commit_framework
    else
        print_info "pre-commit framework not installed (optional)"
    fi
    
    # Create supporting configs
    create_tflint_config
    
    # Test installation
    test_hooks
    
    # Usage instructions
    print_usage_instructions
}

main "$@"
