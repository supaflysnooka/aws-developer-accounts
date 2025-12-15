# AWS Organizations Module

This Terraform module creates and configures AWS Organizations with a well-structured hierarchy of Organizational Units (OUs) and Service Control Policies (SCPs) for governance and security.

## Purpose

This module establishes the foundation for multi-account AWS management by:
- Creating or managing an AWS Organization
- Defining a hierarchical OU structure
- Implementing security guardrails via Service Control Policies
- Enabling AWS service integrations for organization-wide features

## Architecture

```
Root
├── Security OU
├── Infrastructure OU
├── Workloads OU
│   ├── Production OU
│   ├── Staging OU
│   └── Development OU
└── Sandbox OU
```

## Organizational Unit Structure

### Security OU
Purpose: Houses security and compliance-related accounts
- Log Archive account
- Audit account
- Security tooling account

### Infrastructure OU
Purpose: Shared infrastructure services
- Network/Transit account
- Shared Services account
- DNS management account

### Workloads OU
Purpose: Application and service accounts
- **Production**: Production workload accounts
- **Staging**: Staging/pre-production accounts
- **Development**: Development and testing accounts

### Sandbox OU
Purpose: Experimentation and learning
- Individual developer sandboxes
- POC and testing accounts

## Service Control Policies (SCPs)

This module implements several security-focused SCPs:

### DenyLeaveOrganization
**Scope**: Root (all accounts)
**Purpose**: Prevents accounts from leaving the organization
**Actions Denied**: `organizations:LeaveOrganization`

### RequireMFAForSensitiveOperations
**Scope**: Production OU
**Purpose**: Requires MFA for destructive operations
**Actions Protected**:
- EC2 instance stop/termination
- RDS instance/cluster deletion
- S3 bucket deletion

### DenyRootUserAccess
**Scope**: Production OU
**Purpose**: Prevents root user from performing any actions
**Exceptions**: Account management operations

### RequireS3Encryption
**Scope**: Workloads OU
**Purpose**: Enforces encryption for S3 buckets and objects
**Requirements**:
- Server-side encryption (AES256 or KMS)
- Applies to all PutObject operations

### RestrictRegions (Optional)
**Scope**: Root (all accounts)
**Purpose**: Limits operations to approved AWS regions
**Configurable**: Enable via `restrict_regions` variable
**Exceptions**: Global services (IAM, Route53, CloudFront, etc.)

### EnableAWSConfig (Optional)
**Scope**: Root (all accounts)
**Purpose**: Prevents disabling AWS Config
**Actions Denied**: Config deletion and stopping

### ProtectCloudTrail (Optional)
**Scope**: Root (all accounts)
**Purpose**: Protects CloudTrail from tampering
**Actions Denied**: Trail deletion, stopping, and updates

## Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.5.0
- Management account credentials (organization must be created in the management account)
- S3 backend already deployed (from terraform-backend module)

## Usage

### Basic Deployment

1. **Configure backend** in `main.tf`:
```hcl
backend "s3" {
  bucket         = "your-state-bucket-name"
  key            = "bootstrap/organization/terraform.tfstate"
  region         = "us-west-2"
  dynamodb_table = "terraform-state-locks"
  encrypt        = true
}
```

2. **Create terraform.tfvars**:
```hcl
region       = "us-west-2"
feature_set  = "ALL"

# Optional: Restrict regions
restrict_regions = true
approved_regions = ["us-east-1", "us-west-2"]

# Optional: Additional protections
enable_aws_config   = true
protect_cloudtrail  = true
```

3. **Initialize and deploy**:
```bash
terraform init
terraform plan
terraform apply
```

### Advanced Configuration

#### Custom AWS Service Integrations
```hcl
aws_service_access_principals = [
  "cloudtrail.amazonaws.com",
  "config.amazonaws.com",
  "guardduty.amazonaws.com",
  "securityhub.amazonaws.com",
  "sso.amazonaws.com"
]
```

#### Enable All Policy Types
```hcl
enabled_policy_types = [
  "SERVICE_CONTROL_POLICY",
  "TAG_POLICY",
  "BACKUP_POLICY",
  "AISERVICES_OPT_OUT_POLICY"
]
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| region | AWS region for the provider | string | us-west-2 | no |
| feature_set | Organization feature set (ALL or CONSOLIDATED_BILLING) | string | ALL | no |
| enabled_policy_types | List of policy types to enable | list(string) | See variables.tf | no |
| aws_service_access_principals | AWS services to integrate | list(string) | See variables.tf | no |
| restrict_regions | Enable region restrictions | bool | false | no |
| approved_regions | Approved regions (if restriction enabled) | list(string) | [us-east-1, us-west-2] | no |
| enable_aws_config | Enforce AWS Config | bool | true | no |
| protect_cloudtrail | Protect CloudTrail from changes | bool | true | no |

## Outputs

| Name | Description |
|------|-------------|
| organization_id | The ID of the organization |
| organization_arn | The ARN of the organization |
| organization_root_id | The ID of the root OU |
| organization_master_account_id | Management account ID |
| ou_*_id | IDs of all organizational units |
| organizational_units | Map of all OUs and their IDs |
| service_control_policies | Map of all SCPs and their IDs |

## Post-Deployment Steps

### 1. Move Accounts to Appropriate OUs

After deployment, move existing accounts to the appropriate OUs:

```bash
# Get account ID
ACCOUNT_ID="123456789012"

# Get target OU ID
TARGET_OU=$(terraform output -raw ou_production_id)

# Move account
aws organizations move-account \
  --account-id $ACCOUNT_ID \
  --source-parent-id $(terraform output -raw organization_root_id) \
  --destination-parent-id $TARGET_OU
```

### 2. Create Additional Accounts

Use AWS Organizations console or CLI to create new accounts:

```bash
aws organizations create-account \
  --email production@example.com \
  --account-name "Production Workload 1"
```

Then move to the appropriate OU.

### 3. Enable AWS IAM Identity Center (SSO)

For centralized access management:
1. Navigate to IAM Identity Center in AWS Console
2. Enable IAM Identity Center
3. Configure identity source (Active Directory, Okta, etc.)
4. Create permission sets and assign to OUs

### 4. Review and Test SCPs

Before enforcing in production:
1. Test SCPs in Sandbox OU first
2. Use AWS CloudTrail to identify potential issues
3. Gradually roll out to other OUs
4. Monitor for denied actions in CloudTrail

## SCP Testing Strategy

### Test SCP Before Applying

1. **Create test account** in Sandbox OU
2. **Attach SCP** to Sandbox OU
3. **Attempt restricted actions** to verify they're blocked
4. **Check CloudTrail** for denied actions
5. **Refine policy** based on results
6. **Apply to production OUs** once validated

### Example Test Commands

```bash
# Test MFA requirement (should fail without MFA)
aws ec2 terminate-instances --instance-ids i-1234567890abcdef0

# Test S3 encryption (should fail without encryption)
aws s3 cp test.txt s3://mybucket/

# Test region restriction (should fail for non-approved region)
aws ec2 describe-instances --region eu-west-1
```

## Security Best Practices

### Implemented
- Multi-layered OU structure for isolation
- SCPs enforcing security baselines
- Root user access restrictions
- Encryption requirements
- CloudTrail and Config protection

### Recommended Additional Steps

1. **Enable AWS CloudTrail organization trail**:
```bash
aws cloudtrail create-trail \
  --name organization-trail \
  --s3-bucket-name your-trail-bucket \
  --is-organization-trail \
  --is-multi-region-trail
```

2. **Enable AWS GuardDuty across organization**:
```bash
aws guardduty create-detector --enable
aws guardduty create-members --detector-id <detector-id> \
  --account-details AccountId=<account-id>,Email=<email>
```

3. **Enable AWS Security Hub**:
```bash
aws securityhub enable-security-hub
aws securityhub create-members --account-details <account-details>
```

4. **Implement Tag Policies** for resource tagging governance

5. **Configure AWS Backup Policies** for data protection

## Troubleshooting

### Error: Organization Already Exists

```
Error: creating AWS Organizations Organization: OrganizationAlreadyExistsException
```

**Solution**: Import existing organization:
```bash
terraform import aws_organizations_organization.main <organization-id>
```

### Error: SCP Limit Reached

AWS has a default limit of 5 SCPs per OU.

**Solution**: Request a service limit increase or consolidate SCPs.

### Error: Cannot Move Account

```
Error: Account is still a member of organization
```

**Solution**: Ensure account is not the management account. Only member accounts can be moved.

### Denied Actions After SCP Application

Check CloudTrail for denied actions:
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=<ActionName> \
  --max-results 10
```

Review SCP and adjust if legitimate action was blocked.

## Modifying OUs and SCPs

### Adding a New OU

1. **Add resource** to `main.tf`:
```hcl
resource "aws_organizations_organizational_unit" "compliance" {
  name      = "Compliance"
  parent_id = aws_organizations_organization.main.roots[0].id
  
  tags = {
    Name      = "Compliance"
    Purpose   = "Compliance and audit workloads"
    ManagedBy = "terraform"
  }
}
```

2. **Add output** to `outputs.tf`:
```hcl
output "ou_compliance_id" {
  description = "The ID of the Compliance OU"
  value       = aws_organizations_organizational_unit.compliance.id
}
```

3. **Apply changes**:
```bash
terraform apply
```

### Modifying an SCP

1. **Update SCP content** in `main.tf`
2. **Plan changes** to review impact:
```bash
terraform plan
```
3. **Apply changes**:
```bash
terraform apply
```

**WARNING**: SCP changes take effect immediately and may block legitimate operations.

### Detaching an SCP

```bash
# List attachments
aws organizations list-policies-for-target --target-id <ou-id> --filter SERVICE_CONTROL_POLICY

# Detach policy
aws organizations detach-policy --policy-id <policy-id> --target-id <ou-id>
```

## Maintenance

### Regular Reviews

- **Quarterly**: Review SCP effectiveness and adjust as needed
- **Monthly**: Audit account placement in OUs
- **Weekly**: Review CloudTrail for denied actions

### Monitoring

Set up CloudWatch alarms for:
- Changes to organization structure
- SCP attachment/detachment
- Account creation/removal
- Failed API calls due to SCPs

### Updating AWS Service Integrations

As new AWS services are released, update the `aws_service_access_principals` variable to enable organization-wide features.

## Cost Considerations

AWS Organizations itself has no additional cost. However, enabling certain features incurs charges:
- AWS Config: Per configuration item recorded
- CloudTrail: Per event recorded (organization trail)
- GuardDuty: Per GB analyzed
- Security Hub: Per security check per account

## Migration from Existing Organization

If you have an existing AWS Organization:

1. **Import organization**:
```bash
terraform import aws_organizations_organization.main <org-id>
```

2. **Import existing OUs**:
```bash
terraform import aws_organizations_organizational_unit.security <ou-id>
```

3. **Import existing policies**:
```bash
terraform import aws_organizations_policy.deny_leave_organization <policy-id>
```

4. **Verify state**:
```bash
terraform plan
```

5. **Apply only necessary changes**:
```bash
terraform apply
```

## Related Documentation

- [AWS Organizations User Guide](https://docs.aws.amazon.com/organizations/latest/userguide/)
- [Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [AWS Organizations Best Practices](https://aws.amazon.com/organizations/getting-started/best-practices/)
- [AWS Multi-Account Strategy](https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/)

## Next Steps

After deploying the organization module:
1. Review and test all SCPs in a non-production environment
2. Deploy the control-tower module for advanced governance
3. Set up centralized logging and security monitoring
4. Implement AWS IAM Identity Center for SSO
5. Create additional accounts as needed
