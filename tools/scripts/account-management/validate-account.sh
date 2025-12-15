#!/bin/bash
# scripts/validate-account.sh
# Validate developer account configuration and compliance

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Verbose flag
VERBOSE=false
JSON_OUTPUT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        -h|--help)
            cat << EOF
Validate Developer Account Configuration
========================================

Validates that a developer account is properly configured and compliant.

USAGE:
    $0 <account-name> [OPTIONS]

ARGUMENTS:
    account-name    Name of the developer account (e.g., bose-dev-frank-caputo)

OPTIONS:
    --verbose, -v   Show detailed check results
    --json          Output results in JSON format
    -h, --help      Show this help message

EXAMPLES:
    $0 bose-dev-frank-caputo
    $0 bose-dev-frank-caputo --verbose
    $0 bose-dev-frank-caputo --json > results.json

CHECKS PERFORMED:
    ✓ Account exists in AWS Organizations
    ✓ Account is in correct Organizational Unit
    ✓ Permission boundary policy exists
    ✓ DeveloperRole exists and has boundary attached
    ✓ Budget is configured
    ✓ Required tags are present
    ✓ OrganizationAccountAccessRole exists

EXIT CODES:
    0 - All checks passed
    1 - One or more checks failed
    2 - Script error (invalid arguments, missing tools, etc.)
EOF
            exit 0
            ;;
        *)
            ACCOUNT_NAME="$1"
            shift
            ;;
    esac
done

# Validation functions
print_check() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -n "  Checking $1... "
    fi
}

print_pass() {
    PASSED=$((PASSED + 1))
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${GREEN}✓ PASS${NC}"
        if [ "$VERBOSE" = true ] && [ -n "$1" ]; then
            echo "    └─ $1"
        fi
    fi
}

print_fail() {
    FAILED=$((FAILED + 1))
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${RED}✗ FAIL${NC}"
        if [ -n "$1" ]; then
            echo "    └─ $1"
        fi
    fi
}

print_warning() {
    WARNINGS=$((WARNINGS + 1))
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${YELLOW}⚠ WARNING${NC}"
        if [ -n "$1" ]; then
            echo "    └─ $1"
        fi
    fi
}

# Check if account name is provided
if [ -z "$ACCOUNT_NAME" ]; then
    echo -e "${RED}ERROR: Account name is required${NC}" >&2
    echo "Usage: $0 <account-name> [--verbose] [--json]"
    exit 2
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI is not installed${NC}" >&2
    exit 2
fi

# Check if jq is installed (needed for JSON parsing)
if ! command -v jq &> /dev/null; then
    echo -e "${RED}ERROR: jq is not installed${NC}" >&2
    echo "Install with: sudo apt-get install jq (Ubuntu) or brew install jq (Mac)"
    exit 2
fi

# Verify AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}ERROR: AWS credentials not configured${NC}" >&2
    echo "Run: aws sso login --profile <your-profile>"
    exit 2
fi

if [ "$JSON_OUTPUT" = false ]; then
    echo -e "${CYAN}Validating account: $ACCOUNT_NAME${NC}"
    echo ""
fi

# Initialize results array for JSON output
if [ "$JSON_OUTPUT" = true ]; then
    RESULTS="[]"
fi

add_result() {
    local check_name="$1"
    local status="$2"
    local message="$3"
    
    if [ "$JSON_OUTPUT" = true ]; then
        RESULTS=$(echo "$RESULTS" | jq --arg name "$check_name" --arg status "$status" --arg msg "$message" \
            '. += [{"check": $name, "status": $status, "message": $msg}]')
    fi
}

# Check 1: Account exists in AWS Organizations
if [ "$JSON_OUTPUT" = false ]; then
    echo "Organization Checks:"
fi

print_check "Account exists in AWS Organizations"
ACCOUNT_JSON=$(aws organizations list-accounts --query "Accounts[?Name=='$ACCOUNT_NAME']" --output json 2>&1)
if echo "$ACCOUNT_JSON" | jq -e '. | length > 0' &> /dev/null; then
    ACCOUNT_ID=$(echo "$ACCOUNT_JSON" | jq -r '.[0].Id')
    ACCOUNT_STATUS=$(echo "$ACCOUNT_JSON" | jq -r '.[0].Status')
    print_pass "Account ID: $ACCOUNT_ID, Status: $ACCOUNT_STATUS"
    add_result "account_exists" "PASS" "Account ID: $ACCOUNT_ID, Status: $ACCOUNT_STATUS"
else
    print_fail "Account not found in AWS Organizations"
    add_result "account_exists" "FAIL" "Account not found in AWS Organizations"
    
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "Validation failed - account does not exist"
    fi
    exit 1
fi

# Check 2: Account is in correct OU
print_check "Account organizational unit"
PARENT_ID=$(aws organizations list-parents --child-id "$ACCOUNT_ID" --query 'Parents[0].Id' --output text 2>&1)
if [ -n "$PARENT_ID" ] && [ "$PARENT_ID" != "None" ]; then
    OU_NAME=$(aws organizations describe-organizational-unit --organizational-unit-id "$PARENT_ID" --query 'OrganizationalUnit.Name' --output text 2>/dev/null || echo "Unknown")
    print_pass "OU: $OU_NAME ($PARENT_ID)"
    add_result "organizational_unit" "PASS" "OU: $OU_NAME"
else
    print_warning "Could not determine organizational unit"
    add_result "organizational_unit" "WARNING" "Could not determine OU"
fi

if [ "$JSON_OUTPUT" = false ]; then
    echo ""
    echo "IAM Checks:"
fi

# Assume role to check resources in the account
print_check "OrganizationAccountAccessRole exists"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/OrganizationAccountAccessRole"

CREDENTIALS=$(aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name "validation-session" \
    --output json 2>&1)

if [ $? -eq 0 ]; then
    print_pass "Role is assumable"
    add_result "org_access_role" "PASS" "OrganizationAccountAccessRole exists and is assumable"
    
    # Export credentials
    export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.Credentials.SessionToken')
    
    # Check 3: Permission boundary policy exists
    print_check "DeveloperPermissionsBoundary policy exists"
    BOUNDARY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/DeveloperPermissionsBoundary"
    POLICY_EXISTS=$(aws iam get-policy --policy-arn "$BOUNDARY_ARN" --query 'Policy.Arn' --output text 2>&1)
    
    if [ "$POLICY_EXISTS" == "$BOUNDARY_ARN" ]; then
        print_pass "Policy exists"
        add_result "permission_boundary_policy" "PASS" "DeveloperPermissionsBoundary policy exists"
    else
        print_fail "Permission boundary policy not found"
        add_result "permission_boundary_policy" "FAIL" "DeveloperPermissionsBoundary policy not found"
    fi
    
    # Check 4: DeveloperRole exists and has boundary
    print_check "DeveloperRole exists"
    ROLE_JSON=$(aws iam get-role --role-name DeveloperRole --output json 2>&1)
    
    if echo "$ROLE_JSON" | jq -e '.Role' &> /dev/null; then
        ROLE_BOUNDARY=$(echo "$ROLE_JSON" | jq -r '.Role.PermissionsBoundary.PermissionsBoundaryArn // "None"')
        
        if [ "$ROLE_BOUNDARY" == "$BOUNDARY_ARN" ]; then
            print_pass "Role has correct permission boundary"
            add_result "developer_role" "PASS" "DeveloperRole has correct permission boundary"
        elif [ "$ROLE_BOUNDARY" == "None" ]; then
            print_fail "DeveloperRole exists but has no permission boundary"
            add_result "developer_role" "FAIL" "DeveloperRole missing permission boundary"
        else
            print_warning "DeveloperRole has different boundary: $ROLE_BOUNDARY"
            add_result "developer_role" "WARNING" "DeveloperRole has unexpected boundary"
        fi
    else
        print_warning "DeveloperRole does not exist"
        add_result "developer_role" "WARNING" "DeveloperRole not found (may not be required)"
    fi
    
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "Budget Checks:"
    fi
    
    # Check 5: Budget exists
    print_check "Budget configuration"
    BUDGETS=$(aws budgets describe-budgets --account-id "$ACCOUNT_ID" --output json 2>&1)
    
    if echo "$BUDGETS" | jq -e '.Budgets | length > 0' &> /dev/null; then
        BUDGET_COUNT=$(echo "$BUDGETS" | jq '.Budgets | length')
        BUDGET_AMOUNT=$(echo "$BUDGETS" | jq -r '.Budgets[0].BudgetLimit.Amount' 2>/dev/null || echo "Unknown")
        print_pass "Found $BUDGET_COUNT budget(s), Limit: \$$BUDGET_AMOUNT"
        add_result "budget" "PASS" "Budget configured with limit: \$$BUDGET_AMOUNT"
    else
        print_warning "No budgets configured"
        add_result "budget" "WARNING" "No budgets found"
    fi
    
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "Tagging Checks:"
    fi
    
    # Check 6: Required tags
    print_check "Account tags"
    ACCOUNT_TAGS=$(aws organizations list-tags-for-resource --resource-id "$ACCOUNT_ID" --output json 2>&1)
    
    if echo "$ACCOUNT_TAGS" | jq -e '.Tags | length > 0' &> /dev/null; then
        TAG_COUNT=$(echo "$ACCOUNT_TAGS" | jq '.Tags | length')
        
        # Check for required tags
        REQUIRED_TAGS=("Environment" "Owner" "CreatedBy")
        MISSING_TAGS=()
        
        for tag in "${REQUIRED_TAGS[@]}"; do
            if ! echo "$ACCOUNT_TAGS" | jq -e ".Tags[] | select(.Key == \"$tag\")" &> /dev/null; then
                MISSING_TAGS+=("$tag")
            fi
        done
        
        if [ ${#MISSING_TAGS[@]} -eq 0 ]; then
            print_pass "All required tags present ($TAG_COUNT total)"
            add_result "tags" "PASS" "All required tags present"
        else
            print_warning "Missing tags: ${MISSING_TAGS[*]}"
            add_result "tags" "WARNING" "Missing recommended tags: ${MISSING_TAGS[*]}"
        fi
    else
        print_warning "No tags found on account"
        add_result "tags" "WARNING" "No tags found"
    fi
    
    # Clean up credentials
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
else
    print_fail "Cannot assume OrganizationAccountAccessRole"
    add_result "org_access_role" "FAIL" "Cannot assume OrganizationAccountAccessRole"
    
    if [ "$JSON_OUTPUT" = false ]; then
        echo "    └─ Cannot perform in-account checks without role access"
    fi
fi

# Summary
if [ "$JSON_OUTPUT" = true ]; then
    # Output JSON results
    jq -n \
        --arg account "$ACCOUNT_NAME" \
        --arg account_id "$ACCOUNT_ID" \
        --argjson passed "$PASSED" \
        --argjson failed "$FAILED" \
        --argjson warnings "$WARNINGS" \
        --argjson checks "$RESULTS" \
        '{
            account_name: $account,
            account_id: $account_id,
            timestamp: now | todate,
            summary: {
                passed: $passed,
                failed: $failed,
                warnings: $warnings,
                total: ($passed + $failed + $warnings)
            },
            checks: $checks
        }'
else
    echo ""
    echo "================================"
    echo "Validation Summary"
    echo "================================"
    echo -e "Passed:   ${GREEN}$PASSED${NC}"
    echo -e "Failed:   ${RED}$FAILED${NC}"
    echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
    echo "================================"
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ Account validation successful${NC}"
        exit 0
    else
        echo -e "${RED}✗ Account validation failed${NC}"
        echo ""
        echo "Run with --verbose flag for more details"
        exit 1
    fi
fi
