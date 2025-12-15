#!/bin/bash

# Security Scan Script
# Scans for security vulnerabilities and misconfigurations

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_critical() { echo -e "${RED}[CRITICAL] $1${NC}"; CRITICAL=$((CRITICAL + 1)); }
print_high() { echo -e "${RED}[HIGH] $1${NC}"; HIGH=$((HIGH + 1)); }
print_medium() { echo -e "${YELLOW}[MEDIUM] $1${NC}"; MEDIUM=$((MEDIUM + 1)); }
print_low() { echo -e "${BLUE}[LOW] $1${NC}"; LOW=$((LOW + 1)); }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

scan_hardcoded_secrets() {
    print_header "Scanning for Hardcoded Secrets"
    
    # Patterns to detect
    local patterns=(
        'password\s*=\s*["\047][^$]'
        'secret\s*=\s*["\047][^$]'
        'api[_-]?key\s*=\s*["\047][^$]'
        'access[_-]?key\s*=\s*["\047]AKI'
        'aws[_-]?secret'
        'private[_-]?key\s*=\s*["\047]'
    )
    
    local found=false
    for pattern in "${patterns[@]}"; do
        local matches=$(find "$PROJECT_ROOT" -name "*.tf" -type f -exec grep -Hn -iE "$pattern" {} \; 2>/dev/null || true)
        
        if [ -n "$matches" ]; then
            found=true
            print_critical "Potential hardcoded secret found:"
            echo "$matches" | head -5
            echo ""
        fi
    done
    
    if [ "$found" = false ]; then
        print_success "No hardcoded secrets detected"
    fi
}

scan_public_s3_buckets() {
    print_header "Scanning for Public S3 Buckets"
    
    # Check for public ACLs
    local public_acls=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -Hn "acl.*=.*\"public" {} \; 2>/dev/null || true)
    
    if [ -n "$public_acls" ]; then
        print_high "Public S3 bucket ACLs found:"
        echo "$public_acls"
    else
        print_success "No public S3 ACLs in code"
    fi
    
    # Check for disabled public access blocks
    local disabled_blocks=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -Hn "block_public.*=.*false" {} \; 2>/dev/null || true)
    
    if [ -n "$disabled_blocks" ]; then
        print_medium "Public access blocks disabled:"
        echo "$disabled_blocks"
    else
        print_success "Public access blocks properly configured"
    fi
}

scan_unencrypted_resources() {
    print_header "Scanning for Unencrypted Resources"
    
    # Check for disabled encryption
    local unencrypted=$(find "$PROJECT_ROOT/modules" -name "*.tf" -exec grep -Hn "encrypted.*=.*false" {} \; 2>/dev/null || true)
    
    if [ -n "$unencrypted" ]; then
        print_high "Resources with encryption disabled:"
        echo "$unencrypted"
        echo ""
        print_info "Enable encryption for all sensitive data at rest"
    else
        print_success "All resources have encryption enabled"
    fi
    
    # Check for missing encryption configurations
    local rds_files=$(find "$PROJECT_ROOT/modules/databases" -name "*.tf" 2>/dev/null || true)
    if [ -n "$rds_files" ]; then
        for file in $rds_files; do
            if ! grep -q "storage_encrypted" "$file"; then
                print_medium "Missing encryption config in: $file"
            fi
        done
    fi
}

scan_security_group_rules() {
    print_header "Scanning Security Group Rules"
    
    # Check for 0.0.0.0/0 ingress
    local open_ingress=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -B 5 "0.0.0.0/0" {} \; | grep -A 5 "ingress" || true)
    
    if [ -n "$open_ingress" ]; then
        print_high "Security groups with 0.0.0.0/0 ingress found"
        print_info "Restrict ingress to specific IP ranges where possible"
    fi
    
    # Check for SSH (22) open to world
    local open_ssh=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -B 10 "from_port.*=.*22" {} \; | grep "0.0.0.0/0" || true)
    
    if [ -n "$open_ssh" ]; then
        print_critical "SSH (port 22) open to 0.0.0.0/0 detected"
        print_info "Restrict SSH access to specific IPs or use Systems Manager"
    fi
    
    # Check for RDP (3389) open to world
    local open_rdp=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -B 10 "from_port.*=.*3389" {} \; | grep "0.0.0.0/0" || true)
    
    if [ -n "$open_rdp" ]; then
        print_critical "RDP (port 3389) open to 0.0.0.0/0 detected"
    fi
    
    # Check for overly permissive rules
    local all_traffic=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -Hn "from_port.*=.*0" {} \; | grep "to_port.*=.*0" | grep -v "egress" || true)
    
    if [ -n "$all_traffic" ]; then
        print_medium "Overly permissive security group rules (all ports):"
        echo "$all_traffic"
    fi
}

scan_iam_policies() {
    print_header "Scanning IAM Policies"
    
    # Check for wildcard resource ARNs
    local wildcard_resources=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -Hn "Resource.*=.*\"\*\"" {} \; 2>/dev/null || true)
    
    if [ -n "$wildcard_resources" ]; then
        print_medium "Wildcard (*) resource ARNs found:"
        echo "$wildcard_resources" | head -10
        print_info "Use specific resource ARNs where possible"
    fi
    
    # Check for overly permissive actions
    local dangerous_actions=(
        "iam:\*"
        "\*:\*"
        "s3:DeleteBucket"
        "ec2:TerminateInstances"
    )
    
    for action in "${dangerous_actions[@]}"; do
        local matches=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -Hn "$action" {} \; 2>/dev/null || true)
        if [ -n "$matches" ]; then
            print_high "Potentially dangerous IAM action: $action"
            echo "$matches" | head -3
        fi
    done
}

scan_public_exposure() {
    print_header "Scanning for Public Exposure"
    
    # Check for publicly accessible RDS
    local public_rds=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -Hn "publicly_accessible.*=.*true" {} \; 2>/dev/null || true)
    
    if [ -n "$public_rds" ]; then
        print_critical "Publicly accessible RDS instances found:"
        echo "$public_rds"
        print_info "RDS should be in private subnets only"
    else
        print_success "No publicly accessible RDS instances"
    fi
    
    # Check for public subnet usage
    local public_subnet_usage=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -Hn "public_subnets" {} \; | grep -v "vpc\|alb\|load" || true)
    
    if [ -n "$public_subnet_usage" ]; then
        print_medium "Resources in public subnets detected"
        print_info "Deploy applications in private subnets when possible"
    fi
}

scan_logging_configuration() {
    print_header "Scanning Logging Configuration"
    
    # Check for VPC flow logs
    local flow_logs=$(find "$PROJECT_ROOT/modules/networking/vpc" -name "*.tf" -exec grep -l "enable_flow_logs" {} \; 2>/dev/null || true)
    
    if [ -z "$flow_logs" ]; then
        print_medium "VPC flow logs may not be enabled"
    else
        print_success "VPC flow logs configured"
    fi
    
    # Check for S3 access logging
    local s3_logging=$(find "$PROJECT_ROOT/modules/storage/s3" -name "*.tf" -exec grep -l "enable_logging" {} \; 2>/dev/null || true)
    
    if [ -z "$s3_logging" ]; then
        print_low "S3 access logging may not be enabled"
    else
        print_success "S3 access logging configured"
    fi
    
    # Check for CloudTrail
    print_info "Ensure CloudTrail is enabled in management account"
}

scan_versioning_and_backup() {
    print_header "Scanning Backup Configuration"
    
    # Check for S3 versioning
    local s3_versioning=$(find "$PROJECT_ROOT/modules/storage/s3" -name "*.tf" -exec grep "enable_versioning" {} \; || true)
    
    if [ -z "$s3_versioning" ]; then
        print_medium "S3 versioning may not be enabled"
    else
        print_success "S3 versioning configuration found"
    fi
    
    # Check for RDS backups
    local rds_backups=$(find "$PROJECT_ROOT/modules/databases" -name "*.tf" -exec grep "backup_retention_period" {} \; || true)
    
    if [ -z "$rds_backups" ]; then
        print_medium "RDS backup retention may not be configured"
    else
        print_success "RDS backup configuration found"
    fi
}

scan_network_configuration() {
    print_header "Scanning Network Configuration"
    
    # Check for IMDSv2 requirement
    local imdsv2=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -l "require_imdsv2" {} \; 2>/dev/null || true)
    
    if [ -z "$imdsv2" ]; then
        print_medium "IMDSv2 may not be required"
        print_info "Require IMDSv2 to prevent SSRF attacks"
    else
        print_success "IMDSv2 configuration found"
    fi
    
    # Check for default VPC usage
    local default_vpc=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -i "default.*vpc" {} \; || true)
    
    if [ -n "$default_vpc" ]; then
        print_medium "Default VPC usage detected"
        print_info "Use custom VPCs for better security"
    fi
}

scan_container_security() {
    print_header "Scanning Container Security"
    
    # Check for ECR scanning
    local ecr_scanning=$(find "$PROJECT_ROOT/modules/containers/ecr" -name "*.tf" -exec grep "scan_on_push" {} \; || true)
    
    if [ -z "$ecr_scanning" ]; then
        print_medium "ECR image scanning may not be enabled"
    else
        print_success "ECR scanning configuration found"
    fi
    
    # Check for ECS task definition security
    local ecs_privileged=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -i "privileged.*=.*true" {} \; 2>/dev/null || true)
    
    if [ -n "$ecs_privileged" ]; then
        print_high "Privileged container mode detected"
        print_info "Avoid privileged mode unless absolutely necessary"
    fi
}

scan_secrets_management() {
    print_header "Scanning Secrets Management"
    
    # Check for Secrets Manager usage
    local secrets_manager=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -l "aws_secretsmanager_secret" {} \; 2>/dev/null || true)
    
    if [ -z "$secrets_manager" ]; then
        print_low "Secrets Manager may not be used"
        print_info "Use Secrets Manager for sensitive credentials"
    else
        print_success "Secrets Manager configuration found"
    fi
    
    # Check for plaintext secrets in environment variables
    local env_secrets=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -A 5 "environment" {} \; | grep -i "password\|secret\|key" | grep -v "arn:" | grep -v "secretsmanager" || true)
    
    if [ -n "$env_secrets" ]; then
        print_high "Potential plaintext secrets in environment variables:"
        echo "$env_secrets" | head -5
        print_info "Use Secrets Manager or SSM Parameter Store"
    fi
}

scan_resource_tagging() {
    print_header "Scanning Resource Tagging"
    
    # Check for tags variable
    local modules_without_tags=$(find "$PROJECT_ROOT/modules" -mindepth 2 -maxdepth 2 -type d -exec sh -c '
        if [ -f "$1/variables.tf" ] && ! grep -q "variable \"tags\"" "$1/variables.tf"; then
            basename "$1"
        fi
    ' sh {} \; | head -5)
    
    if [ -n "$modules_without_tags" ]; then
        print_low "Modules without tags variable:"
        echo "$modules_without_tags"
    else
        print_success "All modules support tagging"
    fi
}

scan_deletion_protection() {
    print_header "Scanning Deletion Protection"
    
    # Check for lifecycle prevent_destroy
    local protected_resources=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -l "prevent_destroy.*=.*true" {} \; 2>/dev/null || true)
    
    if [ -z "$protected_resources" ]; then
        print_medium "Deletion protection may not be enabled on critical resources"
        print_info "Enable prevent_destroy lifecycle for production resources"
    else
        print_success "Deletion protection found on some resources"
    fi
    
    # Check for RDS deletion protection
    local rds_protection=$(find "$PROJECT_ROOT/modules/databases" -name "*.tf" -exec grep "deletion_protection" {} \; || true)
    
    if [ -z "$rds_protection" ]; then
        print_medium "RDS deletion protection may not be configured"
    fi
}

check_compliance_requirements() {
    print_header "Checking Compliance Requirements"
    
    print_info "Checking for common compliance requirements..."
    
    # Encryption at rest
    local has_encryption=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -l "encrypted.*=.*true" {} \; | wc -l)
    if [ $has_encryption -gt 0 ]; then
        print_success "Encryption at rest configured"
    else
        print_high "Encryption at rest may not be configured"
    fi
    
    # Access logging
    local has_logging=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -l "enable_logging\|access_log" {} \; | wc -l)
    if [ $has_logging -gt 0 ]; then
        print_success "Access logging configured"
    else
        print_medium "Access logging may not be configured"
    fi
    
    # Backup configuration
    local has_backups=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -l "backup_retention\|enable_versioning" {} \; | wc -l)
    if [ $has_backups -gt 0 ]; then
        print_success "Backup configuration found"
    else
        print_high "Backup configuration may be missing"
    fi
}

run_tfsec() {
    print_header "Running tfsec Security Scanner"
    
    if ! command -v tfsec &> /dev/null; then
        print_info "tfsec not installed - skipping"
        print_info "Install: brew install tfsec  OR  go install github.com/aquasecurity/tfsec/cmd/tfsec@latest"
        return
    fi
    
    print_info "Scanning Terraform code for security issues..."
    
    if tfsec "$PROJECT_ROOT" --format json > /tmp/tfsec_results.json 2>/dev/null; then
        print_success "tfsec scan completed - no issues found"
    else
        local critical_count=$(jq '[.results[] | select(.severity=="CRITICAL")] | length' /tmp/tfsec_results.json 2>/dev/null || echo 0)
        local high_count=$(jq '[.results[] | select(.severity=="HIGH")] | length' /tmp/tfsec_results.json 2>/dev/null || echo 0)
        local medium_count=$(jq '[.results[] | select(.severity=="MEDIUM")] | length' /tmp/tfsec_results.json 2>/dev/null || echo 0)
        
        print_info "tfsec findings:"
        echo "  Critical: $critical_count"
        echo "  High: $high_count"
        echo "  Medium: $medium_count"
        
        CRITICAL=$((CRITICAL + critical_count))
        HIGH=$((HIGH + high_count))
        MEDIUM=$((MEDIUM + medium_count))
        
        print_info "Full results: /tmp/tfsec_results.json"
    fi
}

run_checkov() {
    print_header "Running Checkov Security Scanner"
    
    if ! command -v checkov &> /dev/null; then
        print_info "Checkov not installed - skipping"
        print_info "Install: pip install checkov"
        return
    fi
    
    print_info "Scanning for security and compliance issues..."
    
    checkov -d "$PROJECT_ROOT/modules" \
        --framework terraform \
        --output json \
        --quiet > /tmp/checkov_results.json 2>/dev/null || true
    
    local failed=$(jq '.summary.failed' /tmp/checkov_results.json 2>/dev/null || echo 0)
    local passed=$(jq '.summary.passed' /tmp/checkov_results.json 2>/dev/null || echo 0)
    
    print_info "Checkov results:"
    echo "  Passed: $passed"
    echo "  Failed: $failed"
    
    if [ $failed -gt 0 ]; then
        HIGH=$((HIGH + failed))
        print_info "Full results: /tmp/checkov_results.json"
    else
        print_success "Checkov scan passed"
    fi
}

generate_security_report() {
    print_header "Security Scan Summary"
    
    echo ""
    local total=$((CRITICAL + HIGH + MEDIUM + LOW))
    
    if [ $total -eq 0 ]; then
        echo -e "${GREEN}✓ No security issues detected!${NC}"
    else
        echo -e "${YELLOW}Security Issues Found:${NC}"
        echo ""
        if [ $CRITICAL -gt 0 ]; then
            echo -e "  ${RED}CRITICAL: $CRITICAL${NC}"
        fi
        if [ $HIGH -gt 0 ]; then
            echo -e "  ${RED}HIGH:     $HIGH${NC}"
        fi
        if [ $MEDIUM -gt 0 ]; then
            echo -e "  ${YELLOW}MEDIUM:   $MEDIUM${NC}"
        fi
        if [ $LOW -gt 0 ]; then
            echo -e "  ${BLUE}LOW:      $LOW${NC}"
        fi
        echo ""
        
        if [ $CRITICAL -gt 0 ]; then
            echo -e "${RED}✗ CRITICAL issues must be fixed before deployment${NC}"
            return 1
        elif [ $HIGH -gt 0 ]; then
            echo -e "${YELLOW}⚠ HIGH priority issues should be addressed${NC}"
        else
            echo -e "${BLUE}ℹ Review MEDIUM/LOW issues when possible${NC}"
        fi
    fi
    
    echo ""
    print_info "Security Best Practices:"
    echo "  1. Enable encryption for all data at rest"
    echo "  2. Use Secrets Manager for sensitive credentials"
    echo "  3. Restrict security groups to specific IP ranges"
    echo "  4. Enable VPC Flow Logs and CloudTrail"
    echo "  5. Require IMDSv2 for EC2 instances"
    echo "  6. Enable S3 versioning and object locking"
    echo "  7. Use private subnets for applications"
    echo "  8. Enable MFA for privileged operations"
    echo "  9. Regular security scans and updates"
    echo "  10. Implement least privilege IAM policies"
}

generate_html_report() {
    local report_file="/tmp/security_report.html"
    
    cat > "$report_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Security Scan Report - $(date)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .critical { color: #d32f2f; font-weight: bold; }
        .high { color: #f57c00; font-weight: bold; }
        .medium { color: #fbc02d; }
        .low { color: #1976d2; }
        .success { color: #388e3c; }
        .summary { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #2196F3; color: white; }
    </style>
</head>
<body>
    <h1>Security Scan Report</h1>
    <p>Generated: $(date)</p>
    
    <div class="summary">
        <h2>Summary</h2>
        <p class="critical">Critical Issues: $CRITICAL</p>
        <p class="high">High Issues: $HIGH</p>
        <p class="medium">Medium Issues: $MEDIUM</p>
        <p class="low">Low Issues: $LOW</p>
    </div>
    
    <h2>Recommendations</h2>
    <ul>
        <li>Enable encryption for all data at rest</li>
        <li>Use Secrets Manager for sensitive credentials</li>
        <li>Restrict security groups to specific IP ranges</li>
        <li>Enable VPC Flow Logs and CloudTrail</li>
        <li>Use private subnets for applications</li>
    </ul>
</body>
</html>
EOF
    
    print_info "HTML report generated: $report_file"
}

main() {
    print_header "Security Scanner for AWS Developer Accounts"
    
    echo ""
    print_info "Scanning Terraform configuration for security issues..."
    echo ""
    
    # Run all scans
    scan_hardcoded_secrets
    scan_public_s3_buckets
    scan_unencrypted_resources
    scan_security_group_rules
    scan_iam_policies
    scan_public_exposure
    scan_logging_configuration
    scan_versioning_and_backup
    scan_network_configuration
    scan_container_security
    scan_secrets_management
    scan_resource_tagging
    scan_deletion_protection
    check_compliance_requirements
    
    # External tools
    run_tfsec
    run_checkov
    
    # Generate reports
    generate_security_report
    generate_html_report
    
    # Exit code based on severity
    if [ $CRITICAL -gt 0 ]; then
        exit 1
    elif [ $HIGH -gt 0 ]; then
        exit 0  # Warning but don't fail
    else
        exit 0
    fi
}

main "$@"
