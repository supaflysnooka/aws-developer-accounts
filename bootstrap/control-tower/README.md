# AWS Control Tower Module

This Terraform module deploys and configures AWS Control Tower with guardrails, notifications, and drift detection for comprehensive multi-account governance.

## Purpose

AWS Control Tower provides automated setup and governance for a secure, compliant multi-account AWS environment. This module:
- Deploys Control Tower Landing Zone
- Enables detective and preventive guardrails
- Configures centralized logging
- Sets up drift detection and event notifications
- Integrates with AWS Organizations

## What is AWS Control Tower?

AWS Control Tower automates the setup of a well-architected multi-account environment based on AWS best practices. It provides:
- **Landing Zone**: Pre-configured multi-account environment
- **Guardrails**: Preventive and detective controls
- **Account Factory**: Automated account provisioning
- **Dashboard**: Centralized visibility and compliance reporting

## Architecture

```
Management Account
├── Landing Zone Configuration
│   ├── Centralized Logging → Log Archive Account
│   ├── Security Audit → Audit Account
│   └── Account Factory → Service Catalog
├── Guardrails (SCPs + Config Rules)
│   ├── Detective Controls
│   └── Preventive Controls
├── Governed Regions
└── Event Notifications → SNS → Email
```

## Core Components

### Landing Zone
The foundation that sets up:
- Core accounts (Log Archive, Audit)
- Organizational structure
- Centralized logging
- Baseline guardrails

### Log Archive Account
- Centralized CloudTrail logs
- Config logs and snapshots
- Immutable log storage
- Long-term retention

### Audit Account
- Security tooling access
- Read-only access to all accounts
- Security Hub aggregation
- GuardDuty master account

### Account Factory
- Automated account provisioning via Service Catalog
- Baseline configuration applied automatically
- Network configuration templates
- Consistent account setup

## Guardrails

### Detective Guardrails (Monitoring & Detection)

This module enables the following detective controls:

1. **MFA for Root User** - Detects if MFA is not enabled
2. **S3 Public Read Access** - Detects public read permissions
3. **S3 Public Write Access** - Detects public write permissions
4. **EBS Encryption** - Detects unencrypted EBS volumes
5. **RDS Encryption** - Detects unencrypted RDS instances
6. **RDS Public Snapshots** - Detects publicly accessible snapshots
7. **CloudTrail Enabled** - Detects if CloudTrail is disabled

### Preventive Guardrails (Enforcement)

This module enables the following preventive controls:

1. **Protect CloudTrail** - Prevents changes to CloudTrail
2. **Protect AWS Config** - Prevents changes to Config
3. **Root Account MFA** - Enforces MFA for root user actions

### Additional Production Controls

For production OUs, additional guardrails can be enabled:
- S3 SSL requests only
- EBS optimization enforcement

## Prerequisites

- AWS Organizations already deployed (use organization module first)
- Management account access
- Terraform >= 1.5.0
- S3 backend configured
- Root OU ARN (from organization module)

## Important Notes

### Before Deploying Control Tower

1. **Backup any existing configurations** - Control Tower makes significant changes
2. **Review existing OUs** - Control Tower will create its own OU structure
3. **Plan for downtime** - Initial setup takes 60-90 minutes
4. **Understand costs** - AWS Config, CloudTrail, and GuardDuty have ongoing costs
5. **Test in non-production first** - Always validate in a test environment

### Control Tower Limitations

- Cannot be deployed in a region already using AWS Organizations extensively
- Some guardrails cannot be customized
- Requires specific OU names if integrating with existing Organizations
- Drift detection is important - manual changes can cause drift

## Usage

### Basic Deployment

1. **Configure backend** in `main.tf`:
```hcl
backend "s3" {
  bucket         = "your-state-bucket-name"
  key            = "bootstrap/control-tower/terraform.tfstate"
  region         = "us-west-2"
  dynamodb_table = "terraform-state-locks"
  encrypt        = true
}
```

2. **Get Root OU ARN from organization module**:
```bash
cd ../organization
terraform output organization_root_id
# Get the full ARN from AWS Console or CLI
```

3. **Create terraform.tfvars**:
```hcl
home_region = "us-west-2"

governed_regions = [
  "us-east-1",
  "us-west-2"
]

root_ou_arn = "arn:aws:organizations::123456789012:ou/o-xxxxx/ou-xxxxx"

# Optional: Specify existing accounts
log_archive_account_id = ""  # Leave empty to auto-create
audit_account_id       = ""  # Leave empty to auto-create

# Enable features
enable_detective_guardrails  = true
enable_preventive_guardrails = true
enable_drift_detection       = true
enable_event_notifications   = true

# Notification emails
notification_emails = [
  "security-team@example.com",
  "ops-team@example.com"
]

# Logging retention
logging_retention_days        = 365
access_logging_retention_days = 365
log_retention_days           = 90
```

4. **Initialize and deploy**:
```bash
terraform init
terraform plan  # Review changes carefully
terraform apply  # This will take 60-90 minutes
```

### Advanced Configuration

#### Using Existing Accounts

If you already have Log Archive and Audit accounts:

```hcl
log_archive_account_id = "123456789012"
audit_account_id       = "098765432109"
```

#### Custom KMS Encryption

```hcl
kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/abcd1234-ab12-ab12-ab12-abcdef123456"
```

#### Additional Production Controls

```hcl
production_ou_arn = "arn:aws:organizations::123456789012:ou/o-xxxxx/ou-xxxxx"
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| home_region | AWS home region for Control Tower | string | us-west-2 | no |
| enable_control_tower | Whether to enable Control Tower | bool | true | no |
| landing_zone_version | Control Tower landing zone version | string | 3.3 | no |
| governed_regions | Regions governed by Control Tower | list(string) | [us-east-1, us-west-2] | no |
| security_ou_name | Name of Security OU | string | Security | no |
| sandbox_ou_name | Name of Sandbox OU | string | Sandbox | no |
| log_archive_account_id | Log Archive account ID | string | "" | no |
| audit_account_id | Audit account ID | string | "" | no |
| logging_retention_days | Log retention in days | number | 365 | no |
| root_ou_arn | Root OU ARN for guardrails | string | "" | yes |
| production_ou_arn | Production OU ARN | string | "" | no |
| enable_detective_guardrails | Enable detective guardrails | bool | true | no |
| enable_preventive_guardrails | Enable preventive guardrails | bool | true | no |
| enable_drift_detection | Enable drift detection | bool | true | no |
| enable_event_notifications | Enable event notifications | bool | true | no |
| notification_emails | Email addresses for notifications | list(string) | [] | no |

## Outputs

| Name | Description |
|------|-------------|
| landing_zone_arn | ARN of the landing zone |
| landing_zone_id | Landing zone identifier |
| landing_zone_version | Current landing zone version |
| landing_zone_drift_status | Drift status of landing zone |
| account_factory_portfolio_id | Service Catalog portfolio ID |
| notification_topic_arn | SNS topic ARN for notifications |
| control_tower_status | Summary of Control Tower configuration |

## Post-Deployment Steps

### 1. Verify Landing Zone Deployment

Check the Control Tower console:
```bash
aws controltower list-landing-zones
```

Verify drift status:
```bash
aws controltower get-landing-zone --landing-zone-identifier <landing-zone-id>
```

### 2. Subscribe to Email Notifications

Check your email for SNS subscription confirmations and click the confirmation link.

### 3. Configure Account Factory

1. Open AWS Service Catalog console
2. Navigate to Account Factory product
3. Configure network settings (VPC, subnets, etc.)
4. Set up account provisioning parameters

### 4. Enable Additional AWS Services

Consider enabling organization-wide:
- AWS Security Hub
- Amazon GuardDuty
- AWS Firewall Manager
- Amazon Macie

### 5. Create Your First Account

Using Account Factory:
```bash
# Get portfolio ID
PORTFOLIO_ID=$(terraform output -raw account_factory_portfolio_id)

# Get product ID
PRODUCT_ID=$(aws servicecatalog search-products --filters FullTextSearch=AWS Control Tower Account Factory --query 'ProductViewSummaries[0].ProductId' --output text)

# Provision account
aws servicecatalog provision-product \
  --product-id $PRODUCT_ID \
  --provisioning-artifact-name "AWS Control Tower Account Factory" \
  --provisioned-product-name "MyNewAccount" \
  --provisioning-parameters \
    Key=AccountName,Value="My New Account" \
    Key=AccountEmail,Value="myaccount@example.com" \
    Key=ManagedOrganizationalUnit,Value="Production" \
    Key=SSOUserFirstName,Value="Admin" \
    Key=SSOUserLastName,Value="User" \
    Key=SSOUserEmail,Value="admin@example.com"
```

## Monitoring and Drift Detection

### Understanding Drift

Drift occurs when changes are made outside of Control Tower:
- Manual changes in the AWS Console
- Changes via AWS CLI or SDK
- Terraform changes that conflict with Control Tower

### Checking for Drift

```bash
aws controltower get-landing-zone --landing-zone-identifier <landing-zone-id> \
  --query 'landingZone.driftStatus'
```

Drift statuses:
- `IN_SYNC` - No drift detected
- `DRIFTED` - Manual changes detected
- `UNKNOWN` - Drift check pending

### Resolving Drift

1. **Identify changes** in CloudWatch Logs (if drift detection enabled)
2. **Review changes** to determine if intentional
3. **Repair drift** via Control Tower console or re-run Terraform
4. **Update Terraform** if manual changes should be preserved

### CloudWatch Log Group

Drift detection logs are in:
```
/aws/controltower/drift-detection
```

View logs:
```bash
aws logs tail /aws/controltower/drift-detection --follow
```

## Event Notifications

This module creates EventBridge rules and SNS notifications for Control Tower events:

### Events Captured

- Account creation/deletion
- Guardrail violations
- Drift detection
- Landing zone updates
- Control enablement/disablement

### Event Structure

Events follow this pattern:
```json
{
  "source": ["aws.controltower"],
  "detail-type": ["AWS Service Event via CloudTrail"],
  "detail": {
    "eventName": "CreateManagedAccount",
    "serviceEventDetails": {
      "createManagedAccountStatus": {
        "account": {
          "accountId": "123456789012"
        }
      }
    }
  }
}
```

### Testing Notifications

```bash
# Publish test message
aws sns publish \
  --topic-arn $(terraform output -raw notification_topic_arn) \
  --message "Test notification from Control Tower" \
  --subject "Control Tower Test"
```

## Guardrail Management

### Enabling Additional Guardrails

Add new guardrails by adding resources:

```hcl
resource "aws_controltower_control" "deny_public_rds" {
  control_identifier = "arn:aws:controltower:${var.home_region}::control/AWS-GR_RDS_INSTANCE_PUBLIC_ACCESS_CHECK"
  target_identifier  = var.root_ou_arn
}
```

### Available Guardrails

View available guardrails:
```bash
aws controltower list-enabled-controls --target-identifier <ou-arn>
```

### Guardrail Categories

- **Mandatory**: Cannot be disabled, automatically enabled
- **Strongly Recommended**: Should be enabled for security
- **Elective**: Optional based on requirements

## Updating Control Tower

### Updating Landing Zone Version

1. **Check for updates**:
```bash
aws controltower get-landing-zone --landing-zone-identifier <landing-zone-id> \
  --query 'landingZone.latestAvailableVersion'
```

2. **Update version** in terraform.tfvars:
```hcl
landing_zone_version = "3.4"  # New version
```

3. **Apply changes**:
```bash
terraform plan
terraform apply  # This may take 30-60 minutes
```

### Update Best Practices

- Review release notes before updating
- Test updates in non-production first
- Schedule during maintenance window
- Backup configuration before updating
- Monitor for drift after updating

## Troubleshooting

### Error: Landing Zone Already Exists

If Control Tower is already deployed:
```bash
# Import existing landing zone
terraform import 'aws_controltower_landing_zone.main[0]' <landing-zone-id>
```

### Error: Control Tower Not Available in Region

Control Tower is not available in all regions. Verify:
```bash
aws controltower list-landing-zones --region us-west-2
```

### Guardrail Enablement Fails

Check for:
- Conflicting SCPs from Organizations
- AWS Config not properly configured
- Insufficient permissions
- Service limits reached

### Drift Status Stuck on DRIFTED

1. Check drift detection logs
2. Identify the source of drift
3. Revert manual changes or update Terraform
4. Trigger repair via console or CLI

### Account Factory Provisioning Fails

Common issues:
- Invalid email address
- Email already used for another account
- Insufficient permissions
- Network configuration errors

Check provisioning status:
```bash
aws servicecatalog describe-provisioned-product \
  --id <provisioned-product-id>
```

## Security Best Practices

### Implemented
- Centralized logging to dedicated account
- Guardrails for compliance and security
- Drift detection for unauthorized changes
- Event notifications for auditing
- Encryption for logs and data

### Recommended Additional Steps

1. **Enable AWS Security Hub** across all accounts:
```bash
aws securityhub enable-security-hub --enable-default-standards
```

2. **Enable GuardDuty** organization-wide:
```bash
aws guardduty create-detector --enable --finding-publishing-frequency FIFTEEN_MINUTES
```

3. **Configure AWS Backup** for important resources

4. **Implement AWS Systems Manager** for patch management

5. **Set up AWS Firewall Manager** for centralized WAF rules

6. **Enable Amazon Macie** for data discovery and protection

## Cost Optimization

### Control Tower Costs

Control Tower itself is free, but underlying services have costs:

- **AWS Config**: $0.003 per configuration item per region
- **CloudTrail**: First trail free, additional trails $2.00 per 100,000 events
- **S3 Storage**: $0.023 per GB for logs
- **SNS**: $0.50 per million notifications

### Estimated Monthly Costs

For a typical deployment with 10 accounts:
- AWS Config: $30-50 per account = $300-500
- CloudTrail: $20-30 total
- S3 Storage: $10-30
- Other services: $10-20
- **Total**: $340-580 per month

### Cost Reduction Strategies

1. Adjust Config recording frequency
2. Implement S3 lifecycle policies for logs
3. Use selective resource recording in Config
4. Optimize log retention periods
5. Archive old logs to Glacier

## Migrating from Manual Control Tower

If Control Tower was deployed manually:

1. **Inventory existing resources**:
   - Landing zone configuration
   - Enabled guardrails
   - Account Factory configuration

2. **Import landing zone**:
```bash
terraform import 'aws_controltower_landing_zone.main[0]' <landing-zone-id>
```

3. **Import enabled controls**:
```bash
terraform import 'aws_controltower_control.detect_root_mfa[0]' <control-arn>
```

4. **Verify configuration matches**:
```bash
terraform plan  # Should show no changes
```

## Maintenance and Operations

### Regular Tasks

- **Daily**: Monitor drift status and notifications
- **Weekly**: Review guardrail violations
- **Monthly**: Audit account creation and access
- **Quarterly**: Review and update landing zone version
- **Annually**: Comprehensive security and compliance audit

### Automation Scripts

#### Check Drift Status
```bash
#!/bin/bash
LANDING_ZONE_ID="<your-landing-zone-id>"
DRIFT=$(aws controltower get-landing-zone --landing-zone-identifier $LANDING_ZONE_ID --query 'landingZone.driftStatus' --output text)

if [ "$DRIFT" != "IN_SYNC" ]; then
  echo "WARNING: Control Tower drift detected: $DRIFT"
  # Send alert
fi
```

#### Monitor Account Creation
```bash
#!/bin/bash
aws servicecatalog search-provisioned-products \
  --filters SearchQuery="status:UNDER_CHANGE OR status:TAINTED" \
  --query 'ProvisionedProducts[*].[Name,Status]' \
  --output table
```

## Related Documentation

- [AWS Control Tower User Guide](https://docs.aws.amazon.com/controltower/latest/userguide/)
- [Control Tower Guardrails Reference](https://docs.aws.amazon.com/controltower/latest/userguide/guardrails-reference.html)
- [Account Factory Guide](https://docs.aws.amazon.com/controltower/latest/userguide/account-factory.html)
- [Control Tower Best Practices](https://aws.amazon.com/controltower/features/)

## Next Steps

After deploying Control Tower:
1. Enable additional security services (Security Hub, GuardDuty, Macie)
2. Configure Account Factory with network templates
3. Create additional accounts for your workloads
4. Implement automated account provisioning workflows
5. Set up centralized security monitoring and alerting
6. Document your landing zone configuration and customizations
