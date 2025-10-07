# Validation Scripts

Scripts for ensuring code quality, security, compliance, and cost estimation before deployment.

## Overview

These validation scripts provide automated checks for:
- Terraform syntax and formatting
- Security vulnerabilities and misconfigurations
- Compliance with SOC2, HIPAA, and PCI-DSS standards
- Cost estimation for infrastructure changes
- Code quality and best practices

## Scripts

### `validate-terraform.sh`

**Purpose**: Comprehensive Terraform code quality validation

**Features**:
- Terraform formatting check (`terraform fmt`)
- Syntax validation (`terraform validate`)
- Naming convention enforcement
- Required files verification
- Documentation completeness check
- Security best practices scan
- Cost optimization recommendations
- Tagging standards validation
- Version constraint verification
- Optional: TFLint integration
- Optional: Checkov security scan

**Usage**:

```bash
./validate-terraform.sh
```

**Validation Checks**:

**1. Terraform Installation**
- Verifies Terraform is installed
- Checks version compatibility
- Reports current version

**2. Formatting**
- Runs `terraform fmt -check -recursive`
- Identifies unformatted files
- Suggests fix: `terraform fmt -recursive`

**3. Syntax Validation**
- Validates all `.tf` files
- Checks modules and environments
- Initializes without backend
- Reports syntax errors

**4. Naming Conventions**
- Module names: `lowercase-hyphen-case`
- Variable names: `snake_case`
- Resource names: `snake_case`
- Identifies violations

**5. Required Files**
- Each module must have:
  - `main.tf`
  - `variables.tf`
  - `outputs.tf`
  - `README.md`

**6. Documentation**
- README existence check
- Required sections:
  - Usage
  - Variables
  - Outputs
  - Examples
- Completeness warnings

**7. Security Best Practices**
- Hardcoded secret detection
- Public S3 bucket warnings
- Unencrypted resource detection
- IAM policy review

**8. Cost Optimization**
- Instance type recommendations
- Lifecycle policy suggestions
- Reserved capacity opportunities

**9. Tagging Standards**
- Tags variable existence
- common_tags pattern usage
- Tag completeness

**10. Version Constraints**
- Terraform version specified
- Provider versions pinned
- Module version constraints

**External Tool Integration**:

**TFLint** (if installed):
```bash
# Lint all modules
tflint --recursive --format compact

# Checks:
# - AWS-specific rules
# - Naming conventions
# - Deprecated syntax
# - Unused declarations
```

**Checkov** (if installed):
```bash
# Security and compliance scan
checkov -d modules/ --quiet --compact

# Checks:
# - 800+ security policies
# - CIS benchmarks
# - Compliance frameworks
# - Best practices
```

**Exit Codes**:
- `0` - All checks passed or warnings only
- `1` - Critical errors found

**Example Output**:
```
================================================
Terraform Validation Suite
================================================

✓ Terraform 1.6.0 installed
✓ All files properly formatted
✓ Valid: environments/dev-accounts
✓ Valid: modules/networking/vpc
✓ Module names follow conventions
✓ Variable names follow conventions
✓ Required files check complete
✓ All modules have README files
✓ No hardcoded secrets detected
✓ No public S3 buckets detected
⚠ Consider using t3/t4g instance types (2 findings)
✓ All modules support tagging
✓ All modules have version constraints

Summary:
  Errors: 0
  Warnings: 1

⚠ Validation completed with 1 warning(s)
```

**Integration with CI/CD**:
```yaml
# GitHub Actions
- name: Validate Terraform
  run: ./scripts/validation/validate-terraform.sh
```

---

### `security-scan.sh`

**Purpose**: Comprehensive security vulnerability and misconfiguration scanner

**Features**:
- Hardcoded secret detection
- Public exposure scanning
- Encryption validation
- IAM policy review
- Security group analysis
- Network configuration checks
- Container security
- Secrets management validation
- Compliance requirement checks
- Severity-based reporting
- Integration with tfsec and Checkov

**Usage**:

```bash
./security-scan.sh
```

**Security Checks**:

**1. Hardcoded Secrets** [CRITICAL]
```bash
# Scans for:
- password = "plaintext"
- secret = "hardcoded"
- api_key = "AKIAIOSFODNN7EXAMPLE"
- aws_secret = "value"
- private_key = "-----BEGIN"

# Action: Use Secrets Manager or SSM Parameter Store
```

**2. Public S3 Buckets** [HIGH]
```bash
# Checks for:
- acl = "public-read"
- acl = "public-read-write"
- block_public_access = false

# Action: Enable bucket public access blocks
```

**3. Unencrypted Resources** [HIGH]
```bash
# Validates encryption on:
- RDS: storage_encrypted = true
- S3: sse_algorithm configured
- EBS: encrypted = true
- EFS: encrypted = true

# Action: Enable encryption at rest
```

**4. Security Group Rules** [HIGH/CRITICAL]
```bash
# Dangerous patterns:
- 0.0.0.0/0 ingress on port 22 (SSH) [CRITICAL]
- 0.0.0.0/0 ingress on port 3389 (RDP) [CRITICAL]
- 0.0.0.0/0 on all ports [HIGH]
- Overly permissive rules [MEDIUM]

# Action: Restrict to specific IP ranges
```

**5. IAM Policies** [MEDIUM/HIGH]
```bash
# Checks for:
- Resource = "*" (wildcard resources)
- Action = "*:*" (all actions)
- Effect = "Allow" with dangerous actions:
  - iam:*
  - s3:DeleteBucket
  - ec2:TerminateInstances

# Action: Apply least privilege principle
```

**6. Public Exposure** [CRITICAL]
```bash
# Scans for:
- publicly_accessible = true on RDS
- Resources in public subnets
- Internet-facing load balancers without WAF

# Action: Use private subnets for applications
```

**7. Logging Configuration** [MEDIUM]
```bash
# Verifies:
- VPC Flow Logs enabled
- S3 access logging
- ALB access logs
- CloudTrail (management account)

# Action: Enable comprehensive logging
```

**8. Versioning and Backup** [MEDIUM]
```bash
# Checks:
- S3 versioning enabled
- RDS automated backups
- Backup retention periods

# Action: Enable versioning and backups
```

**9. Network Configuration** [MEDIUM]
```bash
# Validates:
- IMDSv2 requirement
- Default VPC usage
- Network segmentation
- Private subnets for databases

# Action: Follow AWS security best practices
```

**10. Container Security** [MEDIUM]
```bash
# For ECS/ECR:
- ECR image scanning enabled
- No privileged containers
- Security context properly set

# Action: Enable scanning, avoid privileged mode
```

**11. Secrets Management** [HIGH]
```bash
# Verifies:
- Secrets Manager usage
- No plaintext secrets in environment variables
- Secret rotation enabled

# Action: Use Secrets Manager for credentials
```

**12. Resource Tagging** [LOW]
```bash
# Checks:
- Tags variable in all modules
- Data classification tags
- Compliance tags

# Action: Tag all resources appropriately
```

**13. Deletion Protection** [MEDIUM]
```bash
# Validates:
- prevent_destroy lifecycle
- deletion_protection on RDS
- MFA delete on S3

# Action: Enable protection on critical resources
```

**Severity Levels**:
- **CRITICAL**: Immediate security risk, blocks deployment
- **HIGH**: Serious issue, should be addressed
- **MEDIUM**: Best practice violation, review needed
- **LOW**: Informational, consider fixing

**External Tool Integration**:

**tfsec** (if installed):
```bash
# AWS security scanner
tfsec . --format json

# Checks 100+ AWS-specific security rules
# Results integrated into summary
```

**Checkov** (if installed):
```bash
# Policy-as-code scanner
checkov -d modules/ --framework terraform

# Checks 800+ policies across:
# - Security
# - Compliance
# - Best practices
```

**Example Output**:
```
================================================
Security Scanner for AWS Developer Accounts
================================================

================================================
Scanning for Hardcoded Secrets
================================================
✓ No hardcoded secrets detected

================================================
Scanning for Public S3 Buckets
================================================
✓ No public S3 ACLs in code
✓ Public access blocks properly configured

================================================
Scanning for Unencrypted Resources
================================================
✓ All resources have encryption enabled

================================================
Scanning Security Group Rules
================================================
[HIGH] Security groups with 0.0.0.0/0 ingress found
ℹ Restrict ingress to specific IP ranges where possible

================================================
Security Scan Summary
================================================

Security Issues Found:
  CRITICAL: 0
  HIGH:     1
  MEDIUM:   2
  LOW:      1

⚠ HIGH priority issues should be addressed

Security Best Practices:
  1. Enable encryption for all data at rest
  2. Use Secrets Manager for sensitive credentials
  3. Restrict security groups to specific IP ranges
  4. Enable VPC Flow Logs and CloudTrail
  5. Require IMDSv2 for EC2 instances
  6. Enable S3 versioning and object locking
  7. Use private subnets for applications
  8. Enable MFA for privileged operations
  9. Regular security scans and updates
  10. Implement least privilege IAM policies

HTML report generated: /tmp/security_report.html
```

**HTML Report**:
- Interactive web-based report
- Filterable by severity
- Detailed findings with remediation
- Exportable for audit purposes

**Exit Codes**:
- `0` - No critical issues (warnings allowed)
- `1` - Critical issues found (blocks deployment)

**CI/CD Integration**:
```yaml
# Fail on critical issues
- name: Security Scan
  run: |
    ./scripts/validation/security-scan.sh
    if [ $? -ne 0 ]; then
      echo "Critical security issues found"
      exit 1
    fi
```

---

### `compliance-check.sh`

**Purpose**: Validates infrastructure against compliance frameworks (SOC2, HIPAA, PCI-DSS)

**Features**:
- SOC2 Type II validation
- HIPAA compliance checks
- PCI-DSS requirements
- Automated control testing
- Compliance report generation
- Pass/fail/warning categorization
- HTML report output
- Remediation recommendations

**Usage**:

```bash
./compliance-check.sh
```

**Compliance Frameworks**:

**SOC2 Type II Controls**:

**1. Encryption at Rest** [Required]
```bash
# Validates:
- RDS: storage_encrypted = true
- S3: sse_algorithm configured
- EBS: encrypted = true

Pass: All databases/storage encrypted
Fail: Unencrypted resources found
```

**2. Encryption in Transit** [Required]
```bash
# Validates:
- ALB: HTTPS/TLS configured
- RDS: require_ssl = true
- API Gateway: TLS 1.2+

Pass: HTTPS/TLS enforced
Warn: SSL/TLS not explicitly required
```

**3. Access Logging** [Required]
```bash
# Validates:
- VPC Flow Logs enabled
- S3 access logging
- ALB access logs
- CloudTrail (management account)

Pass: Comprehensive logging configured
Fail: Critical logs missing
```

**4. Backup and Retention** [Required]
```bash
# Validates:
- RDS automated backups
- Backup retention periods
- S3 versioning
- Log retention policies

Pass: Backups configured with retention
Fail: No backup retention
```

**5. Network Segmentation** [Required]
```bash
# Validates:
- Public/private/database subnets
- Security groups configured
- Private access for sensitive resources

Pass: Proper network segmentation
Fail: Inadequate segmentation
```

**6. IAM and Access Control** [Required]
```bash
# Validates:
- IAM permission boundaries
- MFA configuration
- IAM roles vs users
- Least privilege

Pass: IAM best practices followed
Warn: Areas for improvement
```

**7. Secrets Management** [Required]
```bash
# Validates:
- Secrets Manager usage
- No hardcoded secrets
- Secret rotation enabled

Pass: Secrets properly managed
Fail: Hardcoded secrets found
```

**8. Monitoring and Alerting** [Required]
```bash
# Validates:
- CloudWatch alarms
- Monitoring variables
- Alert configurations

Pass: Monitoring configured
Warn: Limited monitoring found
```

**9. Data Classification** [Required]
```bash
# Validates:
- Tagging support
- Classification tags
- Data handling policies

Pass: All modules support tagging
Warn: Some modules missing tags
```

**10. Change Management** [Required]
```bash
# Validates:
- Lifecycle protection (prevent_destroy)
- Deletion protection
- Change approval processes

Pass: Protection enabled
Warn: Limited protection found
```

**HIPAA Additional Requirements**:

```bash
# Beyond SOC2, HIPAA requires:

1. KMS Encryption [Required]
   - Customer-managed keys
   - Key rotation enabled
   - Audit logging

2. Extended Audit Retention [Required]
   - Minimum 6-year log retention
   - Immutable audit logs
   - Regular compliance audits

3. Physical Safeguards [Documented]
   - AWS data center controls
   - Physical security policies

4. Business Associate Agreements [Required]
   - BAA with AWS
   - BAA with third-party vendors
```

**PCI-DSS Additional Requirements**:

```bash
# Beyond SOC2, PCI-DSS requires:

1. Network Controls [Required]
   - Network ACLs configured
   - Firewall rules documented
   - Cardholder data isolation

2. WAF Configuration [Required]
   - Web Application Firewall
   - OWASP Top 10 protection
   - DDoS protection

3. Regular Testing [Required]
   - Quarterly vulnerability scans
   - Annual penetration testing
   - Patch management (30 days)

4. Access Controls [Required]
   - Strong authentication
   - Unique user IDs
   - Access logging and monitoring
```

**Example Output**:
```
================================================
Infrastructure Compliance Check
================================================

Checking against compliance standards:
  • SOC2 Type II
  • HIPAA
  • PCI-DSS (basic checks)

================================================
SOC2: Encryption at Rest
================================================
✓ RDS databases require encryption
✓ S3 buckets require encryption
✓ EBS volumes require encryption

================================================
SOC2: Encryption in Transit
================================================
✓ HTTPS/TLS configured for load balancers
⚠ Database SSL/TLS not explicitly required

================================================
SOC2: Access Logging
================================================
✓ VPC Flow Logs enabled
⚠ S3 Access Logging not found
⚠ ALB Access Logs not found
ℹ Ensure CloudTrail is enabled in management account

[... more checks ...]

================================================
Compliance Summary
================================================

Results:
  Passed:   15
  Failed:   2
  Warnings: 5
  Total:    22

✗ Compliance check failed with 2 critical issue(s)

ℹ Note: This automated check covers infrastructure code only.
ℹ Complete compliance requires:
  • Operational procedures and documentation
  • Security training and awareness
  • Incident response procedures
  • Regular audits and assessments
  • Third-party penetration testing
  • Vendor risk management

HTML report generated: /tmp/compliance_report.html
```

**HTML Report Contents**:
- Executive summary
- Control-by-control results
- Remediation recommendations
- Compliance roadmap
- Audit trail

**Compliance Levels**:
- **Pass**: Control fully implemented
- **Fail**: Control missing or inadequate
- **Warn**: Partial implementation or minor gaps

**Remediation Priority**:
1. Fix all failures before production
2. Address warnings for certification
3. Document compensating controls
4. Schedule regular re-assessments

**Exit Codes**:
- `0` - All controls passed
- `1` - One or more controls failed

**CI/CD Integration**:
```yaml
# Block production deploys on failures
- name: Compliance Check
  run: |
    ./scripts/validation/compliance-check.sh
  continue-on-error: false  # Fail pipeline
```

**Audit Preparation**:
```bash
# Generate compliance report for auditors
./scripts/validation
