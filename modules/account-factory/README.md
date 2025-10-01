# Account Factory Module

The Account Factory module automates the creation and configuration of AWS developer accounts within an AWS Organization, including budget controls, IAM configuration, and base infrastructure setup.

## Overview

This module creates:
- AWS Organizations member account
- S3 bucket for Terraform state (with versioning and encryption)
- DynamoDB table for state locking
- IAM permission boundary policy
- IAM DeveloperRole with PowerUserAccess
- Monthly budget with email alerts
- Generated onboarding documentation
- Backend configuration file

## Prerequisites

### AWS Requirements

1. **AWS Organizations enabled** in the management account
2. **IAM Permissions** for the user/role executing Terraform:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "organizations:CreateAccount",
           "organizations:DescribeAccount",
           "organizations:ListAccounts",
           "organizations:CloseAccount",
           "iam:*",
           "sts:AssumeRole",
           "s3:*",
           "dynamodb:*",
           "budgets:*"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

### Local Requirements

- **Terraform** >= 1.5.0
- **AWS CLI** >= 2.x
- **jq** (JSON processor for parsing AWS CLI output)
- **bash** shell

Install jq:
```bash
# macOS
brew install jq

# Linux
sudo apt install jq  # or: sudo yum install jq
```

## How It Works

### Phase 1: Account Creation (Native Terraform)
```
1. Creates AWS Organizations account
2. Waits 60 seconds for account provisioning
```

### Phase 2: Cross-Account Configuration (AWS CLI)
```
3. Assumes OrganizationAccountAccessRole in new account
4. Creates S3 state bucket with:
   - Versioning enabled
   - AES256 encryption
   - Public access blocked
5. Creates DynamoDB lock table
6. Creates IAM permission boundary policy
7. Creates DeveloperRole with permission boundary
8. Creates monthly budget with alerts
```

### Phase 3: Documentation Generation
```
9. Generates backend.tf configuration
10. Generates onboarding.md documentation
```

## Why AWS CLI Instead of Native Terraform?

The module uses AWS CLI commands with `local-exec` provisioners for cross-account resources instead of native Terraform resources due to a **provider configuration limitation**:

**The Problem:**
- Resources in the new account need credentials that don't exist until after the account is created
- Terraform requires provider configuration at plan time, before the account exists
- This creates a chicken-and-egg problem

**The Solution:**
- Use `null_resource` with `local-exec` provisioner
- Dynamically assume the OrganizationAccountAccessRole using AWS CLI
- Export temporary credentials as environment variables
- Execute AWS CLI commands with those credentials

**Alternative Approaches Considered:**
1. **Two-phase Terraform** (create account, then apply again) - Too complex for users
2. **Separate modules** (account creation, then account configuration) - Breaks atomicity
3. **Custom Terraform provider** - Overkill for this use case

The AWS CLI approach provides a single-apply solution that works reliably.

## Usage

### Basic Example

```hcl
module "developer_account" {
  source = "../../modules/account-factory"
  
  developer_name        = "john-smith"
  developer_email       = "john.smith@bose.com"
  budget_limit          = 100
  management_account_id = "123456789012"
}
```

### Complete Example

```hcl
data "aws_caller_identity" "current" {}

module "developer_account" {
  source = "../../modules/account-factory"
  
  # Required
  developer_name        = "john-smith"
  developer_email       = "john.smith@bose.com"
  management_account_id = data.aws_caller_identity.current.account_id
  
  # Optional (with defaults shown)
  budget_limit          = 100
  jira_ticket_id        = "INFRA-123"
  admin_email           = "infrastructure-team@bose.com"
  aws_region            = "us-east-1"
  allowed_regions       = ["us-east-1", "us-west-2"]
  allowed_instance_types = [
    "t3.nano", "t3.micro", "t3.small", "t3.medium",
    "t4g.nano", "t4g.micro", "t4g.small", "t4g.medium"
  ]
}

output "account_id" {
  value = module.developer_account.account_id
}

output "developer_role_arn" {
  value = module.developer_account.developer_role_arn
}
```

## Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `developer_name` | string | Yes | - | Developer identifier (lowercase, alphanumeric, hyphens only) |
| `developer_email` | string | Yes | - | Unique email address for the account |
| `management_account_id` | string | Yes | - | AWS Organizations management account ID |
| `budget_limit` | number | No | 100 | Monthly budget limit in USD (1-1000) |
| `jira_ticket_id` | string | No | "" | Jira ticket for tracking |
| `admin_email` | string | No | "infrastructure-team@bose.com" | Email for admin notifications |
| `aws_region` | string | No | "us-east-1" | Primary AWS region |
| `allowed_regions` | list(string) | No | ["us-east-1", "us-west-2"] | Regions developers can use |
| `allowed_instance_types` | list(string) | No | t3/t4g micro-medium | Allowed EC2 instance types |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `account_id` | string | AWS account ID |
| `account_email` | string | Account email address |
| `terraform_state_bucket` | string | S3 bucket name for Terraform state |
| `terraform_lock_table` | string | DynamoDB table name for state locking |
| `developer_role_arn` | string | ARN of the DeveloperRole |
| `onboarding_doc_path` | string | Path to generated onboarding documentation |

## Email Address Requirements

### Uniqueness
AWS Organizations requires a **globally unique email address** for each account. The email cannot be reused for 90 days after account closure.

### Email Aliasing (Recommended for Testing)
Use the `+` trick with Gmail/Google Workspace:
```hcl
developer_email = "john.smith+dev1@bose.com"  # Routes to john.smith@bose.com
developer_email = "john.smith+dev2@bose.com"  # Different account, same inbox
```

### Production Naming
For production, use actual developer emails:
```hcl
developer_email = "john.smith@bose.com"
```

## Security

### IAM Permission Boundary

The permission boundary restricts what developers can do:

**Allowed:**
- EC2, ECS, EKS, Lambda (compute)
- S3, DynamoDB, RDS (storage/databases)
- VPC, ELB, CloudFront (networking)
- CloudWatch, Logs (monitoring)
- SQS, SNS (messaging)
- Limited IAM (must use permission boundary)

**Denied:**
- AWS Marketplace access
- Expensive EC2 instances (> t3.medium)
- Billing/cost management
- AWS Organizations management
- Regions outside allowed list

**IAM Role Creation:**
Developers can create IAM roles, but they **must** include the permission boundary:
```bash
aws iam create-role \
  --role-name MyAppRole \
  --permissions-boundary arn:aws:iam::<ACCOUNT_ID>:policy/DeveloperPermissionBoundary
```

### Budget Enforcement

| Threshold | Action |
|-----------|--------|
| 80% of budget | Email alert to developer and infrastructure team |
| 90% forecast | Email alert (proactive warning) |
| 100% of budget | Automatic resource termination (future enhancement) |

## Troubleshooting

### Error: EMAIL_ALREADY_EXISTS

**Problem:** Email address is still in use by a suspended account.

**Solution:**
```bash
# Option 1: Use a different email
developer_email = "john.smith+test2@bose.com"

# Option 2: Check for suspended accounts
aws organizations list-accounts --query 'Accounts[?Status==`SUSPENDED`]'

# Option 3: Wait for account closure (up to 90 days)
```

### Error: Cannot assume OrganizationAccountAccessRole

**Problem:** Role hasn't propagated yet.

**Solution:**
- The module includes a 60-second wait, but sometimes AWS needs longer
- Simply run `terraform apply` again
- The `|| true` flags prevent errors from already-created resources

### Error: jq: command not found

**Problem:** jq is not installed.

**Solution:**
```bash
# macOS
brew install jq

# Linux
sudo apt install jq
```

### Debug: See What Commands Are Running

The null_resource provisioners include echo statements for visibility:
```bash
terraform apply
# Watch for:
# "Assuming role in account..."
# "Creating S3 bucket..."
# "Enabling versioning..."
# etc.
```

### Manual Verification

Check resources were created:
```bash
# Configure profile for new account
aws configure set profile.john-smith role_arn arn:aws:iam::<ACCOUNT_ID>:role/DeveloperRole
aws configure set profile.john-smith source_profile default

# Verify S3 bucket
aws s3 ls --profile john-smith | grep terraform-state

# Verify DynamoDB table
aws dynamodb list-tables --profile john-smith | grep terraform-locks

# Verify IAM role
aws iam get-role --role-name DeveloperRole --profile john-smith

# Verify permission boundary
aws iam get-policy --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/DeveloperPermissionBoundary --profile john-smith
```

## Generated Files

After successful apply, find generated documentation:

```
generated/
└── john-smith/
    ├── backend.tf      # Terraform backend configuration
    └── onboarding.md   # Complete onboarding guide
```

### Using Generated Backend Configuration

```bash
# In your Terraform project
cp generated/john-smith/backend.tf .

# Initialize with remote state
terraform init

# Your state is now stored in S3 with DynamoDB locking
```

## Account Deletion

### Terraform Destroy

```bash
terraform destroy
```

**Warning:** This removes resources from Terraform state but the AWS account remains in a **SUSPENDED** state for 90 days.

### Complete Account Closure

1. Remove lifecycle protection:
```hcl
# In module or comment out lifecycle block
lifecycle {
  # prevent_destroy = true  # Comment this out
}
```

2. Destroy via Terraform:
```bash
terraform destroy
```

3. Manually close account (optional, for immediate closure):
```bash
# Via AWS Console: Organizations → Accounts → Close Account
# Or via CLI:
aws organizations close-account --account-id <ACCOUNT_ID>
```

## Testing

### Unit Test

```bash
cd tests/unit/modules/account-factory

# Review test configuration
cat main.tf

# Run test
terraform init
terraform plan
terraform apply

# Verify
cat generated/*/onboarding.md

# Clean up
terraform destroy
```

### Integration Test

See `tests/integration/` for complete workflow tests including:
- Account creation
- Infrastructure deployment
- Application deployment
- Cost tracking
- Budget enforcement

## Module Development

### Adding Features

1. Update `main.tf` with new resources
2. Add variables to `variables.tf`
3. Add outputs to `outputs.tf`
4. Update this README
5. Add tests in `tests/unit/modules/account-factory/`
6. Test thoroughly before merging

### Code Standards

- Use `set -e` in bash provisioners (fail fast)
- Include descriptive echo statements for debugging
- Use `|| echo "May already exist"` for idempotent operations
- Keep JSON policies in locals for readability
- Document all assumptions and limitations

## Future Enhancements

- [ ] Self-service web portal integration
- [ ] Automated resource termination at budget limit
- [ ] VPC creation in account factory (currently manual)
- [ ] Service Catalog integration
- [ ] Automated compliance scanning
- [ ] Cross-region replication for state buckets
- [ ] Slack notifications for budget alerts

## References

- [AWS Organizations Documentation](https://docs.aws.amazon.com/organizations/)
- [AWS Budgets Documentation](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
- [IAM Permission Boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html)
- [Terraform null_resource](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource)</content>
</invoke>
