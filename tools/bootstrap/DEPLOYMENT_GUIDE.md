# Complete Bootstrap Deployment Guide

This guide walks through deploying the complete AWS foundation infrastructure in the correct order.

## Overview

You will deploy three modules in sequence:
1. **terraform-backend** - State storage infrastructure
2. **organization** - AWS Organizations with OUs and SCPs
3. **control-tower** - AWS Control Tower with guardrails

Total deployment time: 2-3 hours (mostly waiting for Control Tower)

## Prerequisites Checklist

- [ ] AWS Management account access with AdministratorAccess
- [ ] AWS CLI installed and configured
- [ ] Terraform >= 1.5.0 installed
- [ ] Unique S3 bucket name chosen (globally unique)
- [ ] Email addresses prepared for notifications
- [ ] Target AWS regions identified
- [ ] Git repository for code version control

## Phase 1: Terraform Backend (15 minutes)

### Step 1.1: Configure Variables

Create `bootstrap/terraform-backend/terraform.tfvars`:
```hcl
region            = "us-west-2"
state_bucket_name = "acme-prod-terraform-state"  # Change to your org name
lock_table_name   = "terraform-state-locks"
```

### Step 1.2: Deploy Backend

```bash
cd bootstrap/terraform-backend
terraform init
terraform plan
terraform apply

# Save outputs for later
terraform output > ../backend-config.txt
```

### Step 1.3: Migrate Backend to Remote State (Optional)

Uncomment the backend block in `main.tf`:
```hcl
backend "s3" {
  bucket         = "acme-prod-terraform-state"
  key            = "bootstrap/terraform-backend/terraform.tfstate"
  region         = "us-west-2"
  dynamodb_table = "terraform-state-locks"
  encrypt        = true
}
```

Migrate:
```bash
terraform init -migrate-state
```

## Phase 2: AWS Organizations (30 minutes)

### Step 2.1: Configure Backend

In `bootstrap/organization/main.tf`, uncomment and configure:
```hcl
backend "s3" {
  bucket         = "acme-prod-terraform-state"
  key            = "bootstrap/organization/terraform.tfstate"
  region         = "us-west-2"
  dynamodb_table = "terraform-state-locks"
  encrypt        = true
}
```

### Step 2.2: Configure Variables

Create `bootstrap/organization/terraform.tfvars`:
```hcl
region       = "us-west-2"
feature_set  = "ALL"

# Enable policy types
enabled_policy_types = [
  "SERVICE_CONTROL_POLICY",
  "TAG_POLICY",
  "BACKUP_POLICY"
]

# AWS service integrations
aws_service_access_principals = [
  "cloudtrail.amazonaws.com",
  "config.amazonaws.com",
  "ram.amazonaws.com",
  "ssm.amazonaws.com",
  "sso.amazonaws.com",
  "tagpolicies.tag.amazonaws.com",
  "backup.amazonaws.com"
]

# Optional: Region restrictions
restrict_regions = true
approved_regions = [
  "us-east-1",
  "us-west-2"
]

# Security features
enable_aws_config  = true
protect_cloudtrail = true
```

### Step 2.3: Deploy Organization

```bash
cd ../organization
terraform init
terraform plan
terraform apply

# Save outputs
terraform output > ../organization-outputs.txt
```

### Step 2.4: Get Root OU ARN

```bash
# Get organization ID
ORG_ID=$(terraform output -raw organization_id)

# Get root OU details
aws organizations list-roots

# Note the ARN format:
# arn:aws:organizations::123456789012:root/o-xxxxx/r-xxxxx
```

## Phase 3: AWS Control Tower (60-90 minutes)

### Step 3.1: Configure Backend

In `bootstrap/control-tower/main.tf`, uncomment and configure:
```hcl
backend "s3" {
  bucket         = "acme-prod-terraform-state"
  key            = "bootstrap/control-tower/terraform.tfstate"
  region         = "us-west-2"
  dynamodb_table = "terraform-state-locks"
  encrypt        = true
}
```

### Step 3.2: Get Required ARNs

You'll need the Root OU ARN and optionally Production OU ARN:

```bash
cd ../organization

# Get organization root ID
ROOT_ID=$(terraform output -raw organization_root_id)

# Get production OU ID
PROD_OU_ID=$(terraform output -raw ou_production_id)

# Construct ARNs (replace with your account ID)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ORG_ID=$(terraform output -raw organization_id)

ROOT_ARN="arn:aws:organizations::${ACCOUNT_ID}:ou/${ORG_ID}/${ROOT_ID}"
PROD_ARN="arn:aws:organizations::${ACCOUNT_ID}:ou/${ORG_ID}/${PROD_OU_ID}"

echo "Root OU ARN: $ROOT_ARN"
echo "Production OU ARN: $PROD_ARN"
```

### Step 3.3: Configure Variables

Create `bootstrap/control-tower/terraform.tfvars`:
```hcl
home_region = "us-west-2"

# Regions to govern
governed_regions = [
  "us-east-1",
  "us-west-2"
]

# OU ARNs from previous step
root_ou_arn       = "arn:aws:organizations::123456789012:ou/o-xxxxx/r-xxxxx"
production_ou_arn = "arn:aws:organizations::123456789012:ou/o-xxxxx/ou-xxxxx"

# Leave empty to let Control Tower create these accounts
log_archive_account_id = ""
audit_account_id       = ""

# Guardrails
enable_detective_guardrails  = true
enable_preventive_guardrails = true

# Monitoring
enable_drift_detection     = true
enable_event_notifications = true

# Notifications
notification_emails = [
  "cloud-ops@example.com",
  "security@example.com"
]

# Retention periods
logging_retention_days        = 365
access_logging_retention_days = 365
log_retention_days           = 90

# OU names (must match Organization module)
security_ou_name = "Security"
sandbox_ou_name  = "Sandbox"
```

### Step 3.4: Deploy Control Tower

```bash
cd ../control-tower
terraform init
terraform plan  # Review carefully!

# This will take 60-90 minutes
terraform apply

# Save outputs
terraform output > ../control-tower-outputs.txt
```

### Step 3.5: Verify Deployment

```bash
# Check landing zone status
aws controltower list-landing-zones

# Check drift status
LANDING_ZONE_ID=$(terraform output -raw landing_zone_id)
aws controltower get-landing-zone --landing-zone-identifier $LANDING_ZONE_ID
```

## Post-Deployment Tasks

### Task 1: Confirm Email Subscriptions

Check your email for SNS subscription confirmations from Control Tower notifications. Click the confirmation links.

### Task 2: Configure IAM Identity Center (SSO)

1. Open AWS Console
2. Navigate to IAM Identity Center
3. Enable IAM Identity Center
4. Configure identity source (AWS Directory, Active Directory, Okta, etc.)
5. Create permission sets
6. Assign users/groups to accounts

### Task 3: Enable Additional Security Services

```bash
# Enable Security Hub
aws securityhub enable-security-hub --enable-default-standards

# Enable GuardDuty
aws guardduty create-detector --enable

# Enable Macie (optional)
aws macie2 enable-macie
```

### Task 4: Configure Account Factory

1. Open AWS Service Catalog console
2. Find "AWS Control Tower Account Factory"
3. Configure default network settings
4. Set up provisioning templates

### Task 5: Create First Account

Test account creation:
```bash
# Get portfolio and product IDs
PORTFOLIO_ID=$(cd bootstrap/control-tower && terraform output -raw account_factory_portfolio_id)

PRODUCT_ID=$(aws servicecatalog search-products \
  --filters FullTextSearch="AWS Control Tower Account Factory" \
  --query 'ProductViewSummaries[0].ProductId' \
  --output text)

# Provision test account in Sandbox
aws servicecatalog provision-product \
  --product-id $PRODUCT_ID \
  --provisioning-artifact-name "AWS Control Tower Account Factory" \
  --provisioned-product-name "TestSandboxAccount" \
  --provisioning-parameters \
    Key=AccountName,Value="Test Sandbox" \
    Key=AccountEmail,Value="test-sandbox@example.com" \
    Key=ManagedOrganizationalUnit,Value="Sandbox" \
    Key=SSOUserFirstName,Value="Test" \
    Key=SSOUserLastName,Value="User" \
    Key=SSOUserEmail,Value="testuser@example.com"

# Monitor provisioning
aws servicecatalog describe-provisioned-product \
  --provisioned-product-name "TestSandboxAccount"
```

## Validation Checklist

After deployment, verify:

- [ ] S3 state bucket created and encrypted
- [ ] DynamoDB lock table created
- [ ] All Terraform states are remote
- [ ] AWS Organization created with all OUs
- [ ] SCPs attached to appropriate OUs
- [ ] Control Tower landing zone deployed
- [ ] Log Archive account created/configured
- [ ] Audit account created/configured
- [ ] Guardrails enabled and reporting compliant
- [ ] Drift status shows IN_SYNC
- [ ] Email notifications received and confirmed
- [ ] CloudWatch logs showing events
- [ ] Test account provisioned successfully

## Common Issues and Solutions

### Issue: S3 Bucket Name Already Exists
**Solution**: Choose a different, globally unique bucket name in terraform.tfvars

### Issue: Organization Already Exists
**Solution**: Import existing organization:
```bash
cd bootstrap/organization
terraform import aws_organizations_organization.main <org-id>
```

### Issue: Control Tower Deployment Fails
**Solution**: Check CloudTrail for specific error. Common causes:
- Conflicting SCPs
- Region not supported
- Service limits reached
- Insufficient permissions

### Issue: Drift Detected Immediately
**Solution**: Some drift is expected initially. Review drift details:
```bash
aws logs tail /aws/controltower/drift-detection --follow
```

### Issue: Account Factory Not Available
**Solution**: Wait 5-10 minutes after Control Tower deployment for Service Catalog to synchronize.

## Maintenance Schedule

### Daily
- Monitor drift status
- Review CloudWatch alarms
- Check notification emails

### Weekly
- Review guardrail compliance
- Audit new account creation
- Check for SCP violations in CloudTrail

### Monthly
- Review and approve pending account requests
- Update guardrails as needed
- Audit user access via IAM Identity Center

### Quarterly
- Review and update landing zone version
- Comprehensive security audit
- Update SCPs based on new requirements
- Review and optimize costs

### Annually
- Full compliance review
- Disaster recovery testing
- Documentation updates
- Architecture review

## Rollback Procedures

### If Deployment Fails

#### Terraform Backend
```bash
cd bootstrap/terraform-backend
terraform destroy
# Clean up any manually created resources
```

#### Organization Module
```bash
cd bootstrap/organization
# Detach SCPs first
terraform destroy
# May need to manually remove accounts from OUs first
```

#### Control Tower
```bash
cd bootstrap/control-tower
terraform destroy
# May need to decommission landing zone via console first
```

### Full Environment Teardown

**WARNING**: This destroys everything. Only for complete rollback.

```bash
# Step 1: Decommission Control Tower (60-90 min)
cd bootstrap/control-tower
terraform destroy

# Step 2: Remove Organization structure
cd ../organization
terraform destroy

# Step 3: Remove backend (careful - destroys all state!)
cd ../terraform-backend
# Remove prevent_destroy lifecycle blocks first
terraform destroy
```

## Next Steps

After successful deployment:

1. **Document your configuration** - Save all terraform.tfvars files securely
2. **Train your team** - Ensure everyone understands the new structure
3. **Create runbooks** - Document common operations
4. **Set up monitoring** - CloudWatch dashboards and alarms
5. **Implement CI/CD** - Automate account provisioning
6. **Regular audits** - Schedule periodic security reviews
7. **Disaster recovery** - Test backup and recovery procedures
8. **Cost optimization** - Monitor and optimize AWS Config, CloudTrail costs

## Support and Resources

- [Main Bootstrap README](../README.md)
- [Terraform Backend README](./terraform-backend/README.md)
- [Organization Module README](./organization/README.md)
- [Control Tower Module README](./control-tower/README.md)
- [AWS Organizations Documentation](https://docs.aws.amazon.com/organizations/)
- [AWS Control Tower Documentation](https://docs.aws.amazon.com/controltower/)

## Terraform Commands Reference

```bash
# View outputs
terraform output
terraform output -raw <output_name>

# View state
terraform show
terraform state list

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Refresh state
terraform refresh

# Import existing resource
terraform import <resource_type>.<resource_name> <resource_id>

# Remove resource from state
terraform state rm <resource_address>

# Targeted apply
terraform apply -target=<resource_address>

# View execution plan as JSON
terraform show -json tfplan

# Generate dependency graph
terraform graph | dot -Tsvg > graph.svg
```

## Conclusion

You now have a production-ready AWS foundation with:
- Secure remote state management
- Well-structured multi-account organization
- Comprehensive governance via Control Tower
- Security guardrails and compliance monitoring
- Automated account provisioning
- Centralized logging and auditing

This foundation supports secure, scalable, and compliant AWS workloads.
