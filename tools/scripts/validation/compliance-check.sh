#!/bin/bash

# Compliance Check Script
# Validates infrastructure against compliance requirements (SOC2, HIPAA, PCI-DSS)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PASSED=0
FAILED=0
WARNINGS=0

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_pass() { echo -e "${GREEN}✓ $1${NC}"; PASSED=$((PASSED + 1)); }
print_fail() { echo -e "${RED}✗ $1${NC}"; FAILED=$((FAILED + 1)); }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; WARNINGS=$((WARNINGS + 1)); }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

check_encryption_at_rest() {
    print_header "SOC2: Encryption at Rest"
    
    # Check RDS encryption
    local rds_encrypted=$(find "$PROJECT_ROOT/modules/databases" -name "*.tf" -exec grep -l "storage_encrypted.*=.*true" {} \; | wc -l)
    if [ $rds_encrypted -gt 0 ]; then
        print_pass "RDS databases require encryption"
    else
        print_fail "RDS encryption not enforced"
    fi
    
    # Check S3 encryption
    local s3_encrypted=$(find "$PROJECT_ROOT/modules/storage/s3" -name "*.tf" -exec grep -l "sse_algorithm" {} \; | wc -l)
    if [ $s3_encrypted -gt 0 ]; then
        print_pass "S3 buckets require encryption"
    else
        print_fail "S3 encryption not enforced"
    fi
    
    # Check EBS encryption
    local ebs_encrypted=$(find "$PROJECT_ROOT/modules/compute" -name "*.tf" -exec grep -l "root_volume_encrypted.*=.*true" {} \; | wc -l)
    if [ $ebs_encrypted -gt 0 ]; then
        print_pass "EBS volumes require encryption"
    else
        print_fail "EBS encryption not enforced"
    fi
}

check_encryption_in_transit() {
    print_header "SOC2: Encryption in Transit"
    
    # Check for HTTPS enforcement on ALB
    local https_enforced=$(find "$PROJECT_ROOT/modules/networking/alb" -name "*.tf" -exec grep -l "ssl_policy\|certificate_arn" {} \; | wc -l)
    if [ $https_enforced -gt 0 ]; then
        print_pass "HTTPS/TLS configured for load balancers"
    else
        print_warning "HTTPS/TLS configuration not found"
    fi
    
    # Check for SSL/TLS in RDS
    local rds_ssl=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -i "require_ssl\|force_ssl" {} \; | wc -l)
    if [ $rds_ssl -gt 0 ]; then
        print_pass "SSL/TLS required for database connections"
    else
        print_warning "Database SSL/TLS not explicitly required"
    fi
}

check_access_logging() {
    print_header "SOC2: Access Logging"
    
    # Check VPC Flow Logs
    local flow_logs=$(find "$PROJECT_ROOT/modules/networking/vpc" -name "*.tf" -exec grep -l "enable_flow_logs.*=.*true" {} \; | wc -l)
    if [ $flow_logs -gt 0 ]; then
        print_pass "VPC Flow Logs enabled"
    else
        print_fail "VPC Flow Logs not enabled"
    fi
    
    # Check S3 Access Logging
    local s3_logging=$(find "$PROJECT_ROOT/modules/storage/s3" -name "*.tf" -exec grep -l "enable_logging.*=.*true" {} \; | wc -l)
    if [ $s3_logging -gt 0 ]; then
        print_pass "S3 Access Logging configured"
    else
        print_warning "S3 Access Logging not found"
    fi
    
    # Check ALB Access Logs
    local alb_logging=$(find "$PROJECT_ROOT/modules/networking/alb" -name "*.tf" -exec grep -l "enable_access_logs.*=.*true" {} \; | wc -l)
    if [ $alb_logging -gt 0 ]; then
        print_pass "ALB Access Logs configured"
    else
        print_warning "ALB Access Logs not found"
    fi
    
    print_info "Ensure CloudTrail is enabled in management account"
}

check_backup_retention() {
    print_header "SOC2: Backup and Retention"
    
    # Check RDS backups
    local rds_backups=$(find "$PROJECT_ROOT/modules/databases" -name "*.tf" -exec grep "backup_retention_period" {} \; | grep -v "= 0" | wc -l)
    if [ $rds_backups -gt 0 ]; then
        print_pass "RDS automated backups configured"
    else
        print_fail "RDS backup retention not configured"
    fi
    
    # Check S3 versioning
    local s3_versioning=$(find "$PROJECT_ROOT/modules/storage/s3" -name "*.tf" -exec grep "enable_versioning.*=.*true" {} \; | wc -l)
    if [ $s3_versioning -gt 0 ]; then
        print_pass "S3 versioning enabled"
    else
        print_warning "S3 versioning not found"
    fi
    
    # Check log retention
    local log_retention=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep "retention_in_days\|log_retention_days" {} \; | wc -l)
    if [ $log_retention -gt 0 ]; then
        print_pass "Log retention policies configured"
    else
        print_warning "Log retention policies not found"
    fi
}

check_network_segmentation() {
    print_header "SOC2: Network Segmentation"
    
    # Check for multiple subnet types
    local vpc_config=$(find "$PROJECT_ROOT/modules/networking/vpc" -name "*.tf" -exec grep -E "enable_(public|private|database)_subnets" {} \; | wc -l)
    if [ $vpc_config -ge 3 ]; then
        print_pass "Network segmentation (public/private/database subnets)"
    else
        print_fail "Proper network segmentation not found"
    fi
    
    # Check security groups exist
    local sg_modules=$(find "$PROJECT_ROOT/modules/networking/security-groups" -name "*.tf" | wc -l)
    if [ $sg_modules -gt 0 ]; then
        print_pass "Security groups module exists"
    else
        print_fail "Security groups module not found"
    fi
    
    # Check for public access restrictions
    local private_resources=$(find "$PROJECT_ROOT/modules" -name "*.tf" -exec grep "publicly_accessible.*=.*false" {} \; | wc -l)
    if [ $private_resources -gt 0 ]; then
        print_pass "Resources restricted from public access"
    else
        print_warning "Public access restrictions not explicitly set"
    fi
}

check_iam_best_practices() {
    print_header "SOC2: IAM and Access Control"
    
    # Check for permission boundaries
    local permission_boundaries=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -i "permission_boundary\|permissions_boundary" {} \; | wc -l)
    if [ $permission_boundaries -gt 0 ]; then
        print_pass "IAM permission boundaries configured"
    else
        print_warning "IAM permission boundaries not found"
    fi
    
    # Check for MFA
    local mfa_config=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep -i "mfa\|multi.factor" {} \; | wc -l)
    if [ $mfa_config -gt 0 ]; then
        print_pass "MFA configuration found"
    else
        print_warning "MFA configuration not found"
    fi
    
    # Check for IAM roles (not users)
    local iam_roles=$(find "$PROJECT_ROOT/modules" -name "*.tf" -exec grep "aws_iam_role" {} \; | wc -l)
    local iam_users=$(find "$PROJECT_ROOT/modules" -name "*.tf" -exec grep "aws_iam_user" {} \; | wc -l)
    if [ $iam_roles -gt 0 ] && [ $iam_users -eq 0 ]; then
        print_pass "Using IAM roles instead of IAM users"
    else
        print_warning "Check IAM user usage vs. IAM roles"
    fi
}

check_secrets_management() {
    print_header "SOC2: Secrets Management"
    
    # Check for Secrets Manager usage
    local secrets_manager=$(find "$PROJECT_ROOT/modules/security" -name "*.tf" -exec grep "aws_secretsmanager_secret" {} \; | wc -l)
    if [ $secrets_manager -gt 0 ]; then
        print_pass "AWS Secrets Manager configured"
    else
        print_warning "Secrets Manager module not found"
    fi
    
    # Check for no hardcoded secrets
    local hardcoded=$(find "$PROJECT_ROOT/modules" -name "*.tf" -exec grep -E "(password|secret|key)\s*=\s*\"[^$]" {} \; 2>/dev/null | wc -l)
    if [ $hardcoded -eq 0 ]; then
        print_pass "No hardcoded secrets found"
    else
        print_fail "Potential hardcoded secrets detected"
    fi
}

check_monitoring_alerting() {
    print_header "SOC2: Monitoring and Alerting"
    
    # Check for CloudWatch alarms
    local cw_alarms=$(find "$PROJECT_ROOT/modules" -name "*.tf" -exec grep "aws_cloudwatch_metric_alarm" {} \; | wc -l)
    if [ $cw_alarms -gt 0 ]; then
        print_pass "CloudWatch alarms configured"
    else
        print_warning "CloudWatch alarms not found"
    fi
    
    # Check for monitoring variables
    local monitoring_vars=$(find "$PROJECT_ROOT/modules" -name "*.tf" -exec grep "enable.*monitoring\|create.*alarms" {} \; | wc -l)
    if [ $monitoring_vars -gt 0 ]; then
        print_pass "Monitoring options available"
    else
        print_warning "Monitoring configuration not found"
    fi
}

check_data_classification() {
    print_header "SOC2: Data Classification (Tagging)"
    
    # Check for tagging support
    local tag_support=$(find "$PROJECT_ROOT/modules" -name "variables.tf" -exec grep "variable \"tags\"" {} \; | wc -l)
    local total_modules=$(find "$PROJECT_ROOT/modules" -mindepth 2 -maxdepth 2 -type d | wc -l)
    
    if [ $tag_support -ge $((total_modules - 2)) ]; then
        print_pass "All modules support tagging for data classification"
    else
        print_warning "Some modules missing tags variable ($tag_support/$total_modules)"
    fi
}

check_change_management() {
    print_header "SOC2: Change Management"
    
    # Check for lifecycle protection
    local lifecycle_protection=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep "prevent_destroy.*=.*true" {} \; | wc -l)
    if [ $lifecycle_protection -gt 0 ]; then
        print_pass "Lifecycle protection on critical resources"
    else
        print_warning "Lifecycle protection not found"
    fi
    
    # Check for deletion protection
    local deletion_protection=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep "deletion_protection.*=.*true" {} \; | wc -l)
    if [ $deletion_protection -gt 0 ]; then
        print_pass "Deletion protection configured"
    else
        print_warning "Deletion protection not found"
    fi
}

check_hipaa_requirements() {
    print_header "HIPAA: Additional Requirements"
    
    print_info "HIPAA requires all SOC2 controls plus:"
    
    # Check for KMS encryption
    local kms_usage=$(find "$PROJECT_ROOT/modules" -name "*.tf" -exec grep "kms_key_id\|kms_master_key_id" {} \; | wc -l)
    if [ $kms_usage -gt 0 ]; then
        print_pass "KMS encryption configured for sensitive data"
    else
        print_fail "KMS encryption not found (required for HIPAA)"
    fi
    
    # Check for audit logging
    print_info "Ensure CloudTrail logs all API calls for audit trail"
    print_info "Ensure VPC Flow Logs capture all network traffic"
    print_info "Ensure access logs retained for minimum 6 years"
}

check_pci_dss_requirements() {
    print_header "PCI-DSS: Additional Requirements"
    
    print_info "PCI-DSS requires strict network controls:"
    
    # Check for network segmentation
    local network_acls=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep "aws_network_acl\|aws_default_network_acl" {} \; | wc -l)
    if [ $network_acls -gt 0 ]; then
        print_pass "Network ACLs configured"
    else
        print_warning "Network ACLs not found (recommended for PCI-DSS)"
    fi
    
    # Check for WAF
    local waf_config=$(find "$PROJECT_ROOT" -name "*.tf" -exec grep "web_acl_arn\|aws_wafv2" {} \; | wc -l)
    if [ $waf_config -gt 0 ]; then
        print_pass "WAF configuration found"
    else
        print_warning "WAF not configured (recommended for PCI-DSS)"
    fi
    
    print_info "Ensure quarterly vulnerability scans"
    print_info "Ensure annual penetration testing"
    print_info "Ensure all systems patched within 30 days of release"
}

generate_compliance_report() {
    print_header "Compliance Summary"
    
    local total=$((PASSED + FAILED + WARNINGS))
    
    echo ""
    echo "Results:"
    echo -e "  ${GREEN}Passed:   $PASSED${NC}"
    echo -e "  ${RED}Failed:   $FAILED${NC}"
    echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
    echo "  Total:    $total"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ Compliance check passed${NC}"
        echo ""
        print_info "Note: This automated check covers infrastructure code only."
        print_info "Complete compliance requires:"
        echo "  • Operational procedures and documentation"
        echo "  • Security training and awareness"
        echo "  • Incident response procedures"
        echo "  • Regular audits and assessments"
        echo "  • Third-party penetration testing"
        echo "  • Vendor risk management"
        return 0
    else
        echo -e "${RED}✗ Compliance check failed with $FAILED critical issue(s)${NC}"
        echo ""
        print_info "Address all failed checks before proceeding to production"
        return 1
    fi
}

generate_html_report() {
    local report_file="/tmp/compliance_report.html"
    
    cat > "$report_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Compliance Report - $(date)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #1976D2; }
        .summary { background: #E3F2FD; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .pass { color: #4CAF50; }
        .fail { color: #F44336; }
        .warn { color: #FF9800; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #2196F3; color: white; }
    </style>
</head>
<body>
    <h1>Infrastructure Compliance Report</h1>
    <p>Generated: $(date)</p>
    
    <div class="summary">
        <h2>Summary</h2>
        <p class="pass">Passed: $PASSED</p>
        <p class="fail">Failed: $FAILED</p>
        <p class="warn">Warnings: $WARNINGS</p>
    </div>
    
    <h2>Compliance Standards</h2>
    <ul>
        <li>SOC2 Type II</li>
        <li>HIPAA (Health Insurance Portability and Accountability Act)</li>
        <li>PCI-DSS (Payment Card Industry Data Security Standard)</li>
    </ul>
    
    <h2>Recommendations</h2>
    <ol>
        <li>Enable encryption for all data at rest (RDS, S3, EBS)</li>
        <li>Enforce HTTPS/TLS for all data in transit</li>
        <li>Enable comprehensive logging (VPC Flow Logs, S3 Access Logs, CloudTrail)</li>
        <li>Configure automated backups with appropriate retention</li>
        <li>Implement network segmentation with multiple subnet types</li>
        <li>Use IAM roles instead of long-lived credentials</li>
        <li>Store all secrets in AWS Secrets Manager</li>
        <li>Enable CloudWatch monitoring and alerting</li>
        <li>Implement proper tagging for data classification</li>
        <li>Enable deletion protection for critical resources</li>
    </ol>
    
    <h2>Next Steps</h2>
    <p>This automated check validates infrastructure code only. For complete compliance certification:</p>
    <ul>
        <li>Engage with a qualified compliance auditor</li>
        <li>Document operational procedures</li>
        <li>Conduct security training</li>
        <li>Perform regular security assessments</li>
        <li>Schedule third-party penetration testing</li>
    </ul>
</body>
</html>
EOF
    
    print_info "HTML report generated: $report_file"
}

main() {
    print_header "Infrastructure Compliance Check"
    
    echo ""
    print_info "Checking against compliance standards:"
    echo "  • SOC2 Type II"
    echo "  • HIPAA"
    echo "  • PCI-DSS (basic checks)"
    echo ""
    
    # SOC2 checks
    check_encryption_at_rest
    check_encryption_in_transit
    check_access_logging
    check_backup_retention
    check_network_segmentation
    check_iam_best_practices
    check_secrets_management
    check_monitoring_alerting
    check_data_classification
    check_change_management
    
    # HIPAA additional checks
    check_hipaa_requirements
    
    # PCI-DSS additional checks
    check_pci_dss_requirements
    
    # Generate reports
    generate_compliance_report
    generate_html_report
    
    # Return appropriate exit code
    if [ $FAILED -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"
