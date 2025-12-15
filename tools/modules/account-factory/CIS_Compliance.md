# CIS AWS Foundations Benchmark Compliance Implementation Guide

## Overview

This guide provides a comprehensive solution to address the CIS benchmark security findings in your AWS developer accounts. The solution includes both Terraform configurations for new accounts and remediation scripts for existing accounts.

## Executive Summary

### Failed CIS Controls Addressed

Based on Bose Professional's CIS benchmark report the following controls are being addressed:

| Control | Severity | Description | Solution |
|---------|----------|-------------|----------|
| Config.1 | **Critical** | AWS Config should be enabled | Terraform + Script |
| IAM.6 | **Critical** | Hardware MFA for root user | **Manual Only** |
| EC2.2 | High | Default SG should not allow traffic | Terraform + Script |
| EC2.13 | High | No SSH from 0.0.0.0/0 | **Manual Review** |
| IAM.11-15 | Medium | Password policy requirements | Terraform + Script |
| IAM.3 | Medium | Rotate access keys every 90 days | **Manual Process** |
| EC2.6 | Medium | VPC flow logging enabled | Terraform + Script |
| IAM.16-17 | Low | Password reuse & expiration | Terraform + Script |
| IAM.18 | Low | AWS Support role | Terraform + Script |

---

## Solution Components

### 1. Terraform Module Enhancement (For New Accounts)

**File:** `cis-compliance-additions.tf`

Add this file to your `modules/account-factory/` directory. It includes:

- AWS Config with service-linked role and S3 bucket
- Default security group restrictions
- VPC Flow Logs to CloudWatch
- IAM password policy (all requirements)
- AWS Support role

**Integration Steps:**

```bash
# 1. Copy the file to your module
cp cis-compliance-additions.tf modules/account-factory/

# 2. Add required variables to your variables.tf
# (see variables-cis-additions.tf for the additions needed)

# 3. Update your module calls to include VPC ID
module "developer_account" {
  source = "./modules/account-factory"
  
  # Existing variables...
  developer_name        = "john-smith"
  developer_email       = "john.smith@boseprofessional.com"
  management_account_id = "your-mgmt-account-id"
  
  # NEW: Required for CIS compliance
  vpc_id = module.vpc.vpc_id  # or however you reference your VPC
  
  tags = {
    Environment = "Development"
    CISCompliance = "Enabled"
  }
}
```

### 2. Remediation Scripts (For Existing Accounts)

**Files:** 
- `apply-cis-compliance.sh` (Bash/Linux/Mac)
- `apply-cis-compliance.ps1` (PowerShell/Windows)

These scripts apply CIS controls to accounts that were created before the compliance enhancements.

**Usage:**

**Bash:**
```bash
# Make executable
chmod +x scripts/apply-cis-compliance.sh

# Run for a single account
./scripts/apply-cis-compliance.sh \
  123456789012 \
  john-smith \
  vpc-abc123def

# With help
./scripts/apply-cis-compliance.sh --help
```

**PowerShell:**
```powershell
# Run for a single account
.\scripts\apply-cis-compliance.ps1 `
  -AccountId 123456789012 `
  -DeveloperName john-smith `
  -VpcId vpc-abc123def

# With help
.\scripts\apply-cis-compliance.ps1 -Help
```

---

## Implementation Plan

### Phase 1: New Accounts

1. **Test with a new account**
   ```bash
   # Create a test account
   terraform plan
   terraform apply
   
   # Validate CIS compliance
   ./scripts/validate-account.sh bose-dev-test-account
   ```

2. **Deploy to production**
   - All new developer accounts will now be CIS compliant by default

### Phase 2: Existing Accounts

1. **Identify existing accounts**
   ```bash
   aws organizations list-accounts \
     --query 'Accounts[?Name!=`null`].[Name,Id]' \
     --output table
   ```

2. **Get VPC IDs for each account**
   ```bash
   # For each account, assume role and get VPC ID
   aws ec2 describe-vpcs \
     --query 'Vpcs[0].VpcId' \
     --output text \
     --profile <account-profile>
   ```

3. **Apply CIS compliance**
   ```bash
   # Create a batch script
   cat > apply-cis-to-all.sh << 'EOF'
   #!/bin/bash
   
   # Format: account-name:account-id:vpc-id
   accounts=(
       "john-smith:123456789012:vpc-abc123"
       "jane-doe:234567890123:vpc-def456"
       "bob-jones:345678901234:vpc-ghi789"
   )
   
   for account in "${accounts[@]}"; do
       IFS=':' read -r name id vpc <<< "$account"
       echo "Applying CIS compliance to $name..."
       ./scripts/apply-cis-compliance.sh $id $name $vpc
       echo "Completed $name"
       echo "----------------------------------------"
       sleep 5
   done
   EOF
   
   chmod +x apply-cis-to-all.sh
   ./apply-cis-to-all.sh
   ```

4. **Validate each account**
   ```bash
   for account in bose-dev-*; do
       ./scripts/validate-account.sh $account
   done
   ```

### Phase 3: Manual Actions (Scheduled)

These CIS controls cannot be automated and require manual intervention:

#### 1. IAM.6 - Hardware MFA for Root User (CRITICAL)

**Per Account:**
1. Log in as root user to developer account
2. Navigate to IAM → Dashboard → Security recommendations
3. Click "Add MFA" next to root user
4. Choose hardware device (U2F security key or hardware TOTP)
5. Follow prompts to register device
6. Test login with MFA

**Recommendation:** Schedule a dedicated session to complete this for all accounts.

#### 2. EC2.13 - Review SSH Security Groups (HIGH)

**Audit Script:**
```bash
#!/bin/bash
# Find security groups allowing SSH from anywhere

for account_id in 123456789012 234567890123 345678901234; do
    echo "Checking account: $account_id"
    
    # Assume role
    creds=$(aws sts assume-role \
        --role-arn "arn:aws:iam::${account_id}:role/OrganizationAccountAccessRole" \
        --role-session-name "ssh-audit" \
        --query 'Credentials' \
        --output json)
    
    export AWS_ACCESS_KEY_ID=$(echo $creds | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $creds | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $creds | jq -r '.SessionToken')
    
    # Find SSH rules from 0.0.0.0/0
    aws ec2 describe-security-groups \
        --filters "Name=ip-permission.from-port,Values=22" \
        --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]].{GroupId:GroupId,GroupName:GroupName}' \
        --output table
    
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    echo "----------------------------------------"
done
```

**Remediation:**
- For each security group found, remove the 0.0.0.0/0 rule
- Replace with specific IP ranges or use AWS Security Groups
- Consider using AWS Systems Manager Session Manager instead of SSH

#### 3. IAM.3 - Access Key Rotation (MEDIUM)

**Setup:**
1. Create calendar reminders for each developer
2. Set reminder for 80 days after key creation
3. Document key rotation process in developer handbook

**Process:**
```bash
# Audit access keys
aws iam list-access-keys --user-name <username>
aws iam get-access-key-last-used --access-key-id <key-id>

# Rotate keys
# 1. Create new key
aws iam create-access-key --user-name <username>

# 2. Update applications with new key
# 3. Test applications

# 4. Delete old key
aws iam delete-access-key --user-name <username> --access-key-id <old-key-id>
```

---

## Validation

### Automated Validation

After applying CIS compliance, validate each account:

```bash
# Run validation script
.scripts/account-management/validate-account.sh bose-dev-john-smith --verbose

# Expected output:
# ✓ Config.1 - AWS Config enabled
# ✓ EC2.2 - Default SG restricted
# ✓ EC2.6 - VPC Flow Logs enabled
# ✓ IAM.11-17 - Password policy configured
# ✓ IAM.18 - Support role exists
```

### Manual Verification Checklist

For each account, verify:

- [ ] AWS Config is recording
  ```bash
  aws configservice describe-configuration-recorder-status
  ```

- [ ] VPC Flow Logs are active
  ```bash
  aws ec2 describe-flow-logs
  ```

- [ ] Default security group has no rules
  ```bash
  aws ec2 describe-security-groups --filters Name=group-name,Values=default
  ```

- [ ] Password policy is set
  ```bash
  aws iam get-account-password-policy
  ```

- [ ] Support role exists
  ```bash
  aws iam get-role --role-name AWSSupportRole
  ```

---

## Cost Impact

### New Monthly Costs Per Account

| Service | Estimated Cost | Notes |
|---------|----------------|-------|
| AWS Config | $2-5/month | Depends on resource count |
| VPC Flow Logs | $0.50-2/month | CloudWatch storage |
| S3 (Config bucket) | $0.10-0.50/month | Minimal storage |
| **Total** | **$2.60-7.50/month** | Per developer account |

### Cost Optimization

- Config bucket has lifecycle policy (delete after 90 days)
- Flow logs have 90-day retention
- Minimal impact on development budgets

---

## Rollback Plan

If issues occur after applying CIS compliance:

### For New Accounts
```bash
# Remove CIS compliance file from module
cd modules/account-factory
git checkout HEAD -- cis-compliance-additions.tf

# Re-deploy without CIS controls
terraform plan
terraform apply
```

### For Existing Accounts

**Disable AWS Config:**
```bash
aws configservice stop-configuration-recorder \
    --configuration-recorder-name cis-config-recorder
aws configservice delete-configuration-recorder \
    --configuration-recorder-name cis-config-recorder
aws configservice delete-delivery-channel \
    --delivery-channel-name cis-config-delivery
```

**Disable VPC Flow Logs:**
```bash
# Get flow log ID
FLOW_LOG_ID=$(aws ec2 describe-flow-logs \
    --filter "Name=resource-id,Values=$VPC_ID" \
    --query 'FlowLogs[0].FlowLogId' \
    --output text)

# Delete flow log
aws ec2 delete-flow-logs --flow-log-ids $FLOW_LOG_ID
```

---

## Ongoing Maintenance

### Monthly Tasks
- Review AWS Config compliance dashboard
- Check for new security group rules allowing 0.0.0.0/0
- Verify VPC Flow Logs are capturing data

### Quarterly Tasks
- Re-run CIS benchmark scan
- Review and update password policy if needed
- Audit IAM access keys for rotation

### Annual Tasks
- Review CIS benchmark updates
- Update automation scripts
- Train new team members on CIS compliance

---

## Troubleshooting

### AWS Config Not Recording

**Symptoms:**
- Config recorder shows "STOPPED"
- No configuration items in Config

**Solution:**
```bash
# Check recorder status
aws configservice describe-configuration-recorder-status

# Start recorder
aws configservice start-configuration-recorder \
    --configuration-recorder-name cis-config-recorder

# Verify S3 bucket policy
aws s3api get-bucket-policy --bucket config-bucket-<account-id>
```

### VPC Flow Logs Not Working

**Symptoms:**
- No logs appearing in CloudWatch
- Flow log shows "FAIL" status

**Solution:**
```bash
# Check flow log status
aws ec2 describe-flow-logs --flow-log-ids <flow-log-id>

# Verify IAM role permissions
aws iam get-role-policy \
    --role-name VPCFlowLogsRole-<developer-name> \
    --policy-name vpc-flow-logs-policy

# Check CloudWatch log group
aws logs describe-log-groups \
    --log-group-name-prefix /aws/vpc/flowlogs/
```

### Password Policy Conflicts

**Symptoms:**
- Error: "Cannot update password policy"

**Solution:**
```bash
# Check current policy
aws iam get-account-password-policy

# If policy already stricter, that's fine
# Only update if needed to meet CIS requirements
```

---

## Additional Resources

### Documentation
- [CIS AWS Foundations Benchmark v1.2.0](https://www.cisecurity.org/benchmark/amazon_web_services)
- [AWS Config Documentation](https://docs.aws.amazon.com/config/)
- [VPC Flow Logs Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html)
- [IAM Password Policy Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_passwords_account-policy.html)

### Internal Documentation
- Getting Started Guide: `GETTING_STARTED.md`
- Validation Scripts: `scripts/validate-account.sh`
- Update Scripts: `scripts/update-existing-acct.sh`

### Support Contacts
- Infrastructure Team: infrastructure-team@boseprofessional.com
- Security Team: security@boseprofessional.com
---

## Summary

This implementation provides:

**Automated CIS compliance for new developer accounts**
**Remediation scripts for existing accounts**  
**Validation and monitoring tools**
**Clear manual action requirements**
**Rollback procedures if needed**

**Next Steps:**
1. Review this guide with your team
2. Test on a single dev account first
3. Roll out to production in phases
4. Schedule manual remediation tasks
5. Set up ongoing monitoring

Questions? Contact Frank Caputo, Anushree G, or Rob Birdwell (AHEAD)
