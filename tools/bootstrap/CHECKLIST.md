# AWS Bootstrap Pre-Deployment Checklist

Use this checklist to ensure you're ready to deploy the AWS foundation infrastructure.

## Prerequisites

### AWS Account Setup
- [ ] AWS account created
- [ ] Root user MFA enabled
- [ ] Billing alerts enabled in console (Preferences → Receive Billing Alerts)
- [ ] Administrative IAM user or role created
- [ ] AWS CLI installed and configured
- [ ] CLI credentials tested: `aws sts get-caller-identity`

### Development Environment
- [ ] Terraform >= 1.5.0 installed: `terraform version`
- [ ] Git installed and configured
- [ ] Text editor or IDE configured
- [ ] Command line terminal access
- [ ] Internet connection (for provider downloads)

### Planning and Documentation
- [ ] Unique S3 bucket name chosen (globally unique)
- [ ] AWS region(s) selected (primary and governed regions)
- [ ] Email addresses collected for billing alerts
- [ ] Email addresses collected for Control Tower notifications
- [ ] Organizational structure designed (OUs and account placement)
- [ ] Budget limits determined
- [ ] Cost approval obtained (estimated $350-600/month)

### Knowledge Requirements
- [ ] Basic understanding of AWS Organizations
- [ ] Familiarity with Terraform basics
- [ ] Understanding of your organization's compliance requirements
- [ ] Knowledge of Git for version control
- [ ] Understanding of AWS billing and cost management

## Module 1: Terraform Backend

### Before Deployment
- [ ] Unique S3 bucket name ready (e.g., `acme-prod-terraform-state`)
- [ ] DynamoDB table name chosen (e.g., `terraform-state-locks`)
- [ ] Primary AWS region selected (e.g., `us-west-2`)
- [ ] Variables file created: `terraform.tfvars`

### Deployment Steps
- [ ] Navigate to `bootstrap/terraform-backend`
- [ ] Run `terraform init`
- [ ] Review with `terraform plan`
- [ ] Apply with `terraform apply`
- [ ] Save outputs: `terraform output > ../backend-config.txt`
- [ ] Optionally migrate to remote state

### Validation
- [ ] S3 bucket created and accessible
- [ ] DynamoDB table created
- [ ] Bucket versioning enabled
- [ ] Bucket encryption enabled
- [ ] Public access blocked

## Module 2: Organization

### Before Deployment
- [ ] Backend configuration added to `main.tf`
- [ ] S3 bucket name from Module 1 ready
- [ ] Region restrictions decided (optional)
- [ ] AWS service integrations reviewed
- [ ] Variables file created: `terraform.tfvars`

### Deployment Steps
- [ ] Navigate to `bootstrap/organization`
- [ ] Uncomment backend block in `main.tf`
- [ ] Run `terraform init`
- [ ] Review with `terraform plan`
- [ ] Apply with `terraform apply`
- [ ] Save outputs: `terraform output > ../organization-outputs.txt`

### Validation
- [ ] AWS Organization created/imported
- [ ] All OUs created (Security, Infrastructure, Workloads, Production, Staging, Development, Sandbox)
- [ ] SCPs created
- [ ] SCPs attached to appropriate OUs
- [ ] Organization root ID obtained

### Post-Deployment
- [ ] Note Root OU ARN for Control Tower: `arn:aws:organizations::<account>:ou/<org-id>/<root-id>`
- [ ] Document OU IDs for future use
- [ ] Test SCP in sandbox account (optional)

## Module 3: Control Tower

### Before Deployment
- [ ] Root OU ARN from Module 2
- [ ] Production OU ARN (optional)
- [ ] Governed regions decided
- [ ] Email addresses for notifications ready
- [ ] Backend configuration added
- [ ] Variables file created
- [ ] 2-3 hours available for deployment

### Deployment Steps
- [ ] Navigate to `bootstrap/control-tower`
- [ ] Construct Root OU ARN
- [ ] Update `terraform.tfvars` with OU ARNs
- [ ] Run `terraform init`
- [ ] Review with `terraform plan` (carefully!)
- [ ] Apply with `terraform apply` (60-90 minutes)
- [ ] Save outputs

### Validation
- [ ] Landing zone deployed successfully
- [ ] Log Archive account created (or configured)
- [ ] Audit account created (or configured)
- [ ] Guardrails enabled and compliant
- [ ] Drift status shows `IN_SYNC`
- [ ] Event notifications configured

### Post-Deployment
- [ ] Confirm email subscriptions (check inbox)
- [ ] Access Control Tower dashboard
- [ ] Verify Account Factory is available
- [ ] Review CloudWatch logs for drift detection

## Module 4: SCP Policies (Optional)

### Before Deployment
- [ ] OU IDs from Module 2
- [ ] Security requirements documented
- [ ] Policies to enable decided
- [ ] Admin role ARNs gathered (for exceptions)
- [ ] Backend configuration added
- [ ] Variables file created

### Deployment Steps
- [ ] Navigate to `bootstrap/scp-policies`
- [ ] Configure which policies to enable
- [ ] Configure policy attachments
- [ ] Run `terraform init`
- [ ] Review with `terraform plan`
- [ ] Apply with `terraform apply`

### Validation
- [ ] Enabled policies created
- [ ] Policies attached to correct OUs
- [ ] Test in sandbox account
- [ ] Verify legitimate actions still work
- [ ] Check CloudTrail for denied actions

### Post-Deployment
- [ ] Document policy impacts
- [ ] Train teams on restrictions
- [ ] Create exception procedures

## Module 5: Billing Alerts (Optional)

### Before Deployment
- [ ] Email addresses for billing alerts ready
- [ ] Monthly budget amount determined
- [ ] Service budgets planned (optional)
- [ ] Tag-based budgets planned (optional)
- [ ] Dashboard services list ready
- [ ] Backend configuration added
- [ ] Variables file created

### Deployment Steps
- [ ] Navigate to `bootstrap/billing-alerts`
- [ ] Configure budgets and thresholds
- [ ] Run `terraform init`
- [ ] Review with `terraform plan`
- [ ] Apply with `terraform apply`

### Validation
- [ ] SNS topic created
- [ ] Budgets created
- [ ] CloudWatch alarms created
- [ ] Anomaly detection enabled (if configured)
- [ ] Dashboard created (if configured)

### Post-Deployment
- [ ] Confirm email subscriptions
- [ ] View dashboard in CloudWatch
- [ ] Test notification (optional)
- [ ] Review initial budget status

## Post-Deployment Tasks

### Immediate (Same Day)
- [ ] All email subscriptions confirmed
- [ ] All module outputs saved
- [ ] Documentation updated with actual values
- [ ] Git repository committed with code
- [ ] Initial backup of state files
- [ ] Team notified of new infrastructure

### First Week
- [ ] Move existing accounts to appropriate OUs
- [ ] Configure IAM Identity Center (SSO)
- [ ] Enable Security Hub
- [ ] Enable GuardDuty
- [ ] Create first test account via Account Factory
- [ ] Monitor for SCP denials
- [ ] Review billing alerts

### First Month
- [ ] Review budget vs actual spending
- [ ] Adjust SCP policies based on feedback
- [ ] Create additional production accounts
- [ ] Implement tagging strategy
- [ ] Set up additional security services
- [ ] Train development teams
- [ ] Document any exceptions or special cases

## Verification Commands

Run these commands to verify your deployment:

```bash
# Verify AWS Organizations
aws organizations describe-organization

# List OUs
aws organizations list-organizational-units-for-parent \
  --parent-id $(aws organizations list-roots --query 'Roots[0].Id' --output text)

# Check Control Tower
aws controltower list-landing-zones

# List budgets
aws budgets describe-budgets \
  --account-id $(aws sts get-caller-identity --query Account --output text)

# Verify state backend
aws s3 ls s3://your-bucket-name/

# Check DynamoDB locks table
aws dynamodb describe-table --table-name terraform-state-locks
```

## Emergency Contacts

Document these before deployment:

- [ ] AWS Support contact method
- [ ] Internal escalation path
- [ ] Terraform expert contact
- [ ] Security team contact
- [ ] Finance/billing contact
- [ ] On-call procedures documented

## Rollback Plan

Prepare rollback procedures:

- [ ] State file backup procedure documented
- [ ] Manual resource cleanup steps documented
- [ ] Terraform destroy order documented
- [ ] Emergency break-glass procedure
- [ ] Communication plan for rollback

## Success Criteria

Deployment is successful when:

- [ ] All modules deployed without errors
- [ ] All email subscriptions confirmed
- [ ] No drift detected in Control Tower
- [ ] Test account created successfully
- [ ] SCPs working as expected
- [ ] Billing alerts functioning
- [ ] Documentation complete
- [ ] Team trained
- [ ] Monitoring in place

## Common Issues Preparation

Be prepared for these common issues:

- [ ] S3 bucket name collision (have backup name ready)
- [ ] IAM permission errors (ensure AdministratorAccess)
- [ ] State lock issues (know how to force-unlock)
- [ ] Email confirmation delay (check spam folder)
- [ ] Control Tower deployment timeout (be patient, can take 90 min)
- [ ] SCP blocking legitimate action (know how to detach)
- [ ] Budget threshold too low (can adjust after deployment)

## Time Estimates

Plan your deployment window:

| Module | Deployment Time | Post-Deploy Time |
|--------|----------------|------------------|
| terraform-backend | 15 minutes | 10 minutes |
| organization | 30 minutes | 30 minutes |
| control-tower | 60-90 minutes | 45 minutes |
| scp-policies | 10 minutes | 30 minutes |
| billing-alerts | 15 minutes | 15 minutes |
| **Total** | **2-3 hours** | **2 hours** |

**Recommended**: Schedule a 4-hour window for full deployment and validation.

## Final Pre-Flight Check

Before starting deployment:

- [ ] All checkboxes above completed
- [ ] Time window scheduled
- [ ] Team notified
- [ ] Backup plan ready
- [ ] Support contacts available
- [ ] Coffee ready ☕

## Ready to Deploy?

If all checkboxes are complete, you're ready to proceed with deployment!

Start with: `cd bootstrap/terraform-backend`

Good luck! 🚀
