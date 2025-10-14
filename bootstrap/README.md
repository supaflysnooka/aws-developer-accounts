# Bootstrap - AWS Foundation Infrastructure

This directory contains Terraform configurations for bootstrapping the foundational AWS infrastructure components. These resources must be created before deploying other infrastructure and are designed to be deployed in a specific order.

## Overview

The bootstrap process sets up the core AWS infrastructure components needed for:
- Terraform state management (S3 + DynamoDB)
- AWS Organizations structure
- AWS Control Tower (if applicable)

## Directory Structure

```
bootstrap/
├── README.md                    # This file
├── terraform-backend/          # Creates S3 bucket and DynamoDB table for state
│   ├── main.tf
│   ├── variables.tf
│   └── .terraform.lock.hcl
├── organization/               # AWS Organizations setup
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── control-tower/              # AWS Control Tower configuration
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── scp-policies/              # Additional Service Control Policies library
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── billing-alerts/            # Billing alerts and budget monitoring
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

## Deployment Order

**IMPORTANT:** Deploy these modules in the following order:

1. **terraform-backend** - Must be deployed first to create state storage
2. **organization** - Sets up AWS Organizations structure
3. **control-tower** - Configures AWS Control Tower (if using)
4. **scp-policies** - (Optional) Additional Service Control Policies
5. **billing-alerts** - (Optional) Billing alerts and budget monitoring

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0 installed
- Administrative access to the AWS management account
- Unique S3 bucket name chosen (must be globally unique)

## Quick Start

### 1. Deploy Terraform Backend

```bash
cd terraform-backend
terraform init
terraform plan -var="state_bucket_name=your-unique-bucket-name" \
               -var="lock_table_name=terraform-state-locks"
terraform apply
```

After deployment, note the outputs - you'll need these for configuring other modules.

### 2. Migrate to Remote State (Optional but Recommended)

After creating the backend resources, you can migrate this module to use remote state:

```bash
# Add backend configuration to main.tf
# See terraform-backend/README.md for details
terraform init -migrate-state
```

### 3. Deploy Organization Module

```bash
cd ../organization
# Configure backend in main.tf using outputs from step 1
terraform init
terraform plan
terraform apply
```

### 4. Deploy Control Tower Module

```bash
cd ../control-tower
# Configure backend in main.tf
terraform init
terraform plan
terraform apply
```

### 5. Deploy SCP Policies Module (Optional)

```bash
cd ../scp-policies
# Configure backend in main.tf
terraform init
terraform plan
terraform apply
```

### 6. Deploy Billing Alerts Module (Optional)

```bash
cd ../billing-alerts
# Configure backend in main.tf
terraform init
terraform plan
terraform apply
```

## State Management

After the initial bootstrap:
- The `terraform-backend` module creates the S3 bucket and DynamoDB table
- All subsequent modules (including terraform-backend itself after migration) should use remote state
- State files are encrypted at rest and versioned
- DynamoDB provides state locking to prevent concurrent modifications

## Important Notes

### State Isolation

Each module in this directory can maintain separate state files in the shared backend:
- `terraform-backend/terraform.tfstate` - Backend infrastructure state
- `organization/terraform.tfstate` - Organization structure state  
- `control-tower/terraform.tfstate` - Control Tower configuration state

### Destruction Prevention

Critical resources include `lifecycle { prevent_destroy = true }` blocks:
- S3 state bucket
- DynamoDB lock table

To destroy these resources, you must first remove the lifecycle blocks.

### Access Control

Ensure proper IAM permissions for:
- Creating S3 buckets and configuring encryption
- Creating DynamoDB tables
- Managing AWS Organizations
- Deploying Control Tower

## Troubleshooting

### Bucket Name Already Exists
S3 bucket names must be globally unique. If you get a "bucket already exists" error, choose a different name.

### State Lock Errors
If you encounter state lock errors:
```bash
# View current locks
aws dynamodb scan --table-name terraform-state-locks

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Permission Denied Errors
Ensure your AWS credentials have sufficient permissions. For initial bootstrap, you typically need:
- `AdministratorAccess` or equivalent permissions
- Access to create S3 buckets and DynamoDB tables

## Module Documentation

See individual README files in each subdirectory for detailed documentation:
- [terraform-backend/README.md](./terraform-backend/README.md) - Terraform state backend setup
- [organization/README.md](./organization/README.md) - AWS Organizations configuration
- [control-tower/README.md](./control-tower/README.md) - AWS Control Tower setup
- [scp-policies/README.md](./scp-policies/README.md) - Additional Service Control Policies
- [billing-alerts/README.md](./billing-alerts/README.md) - Billing alerts and budget monitoring

## Maintenance

### Updating Provider Versions

```bash
# In each module directory
terraform init -upgrade
```

### Reviewing State File Versions

Old state file versions are automatically deleted after 90 days (configurable in lifecycle policy).

## Security Considerations

- S3 bucket encryption enabled (AES256)
- S3 versioning enabled for state recovery
- S3 public access blocked
- DynamoDB encryption at rest (AWS managed)
- State locking prevents concurrent modifications
- Ensure IAM policies restrict access to state bucket
- Consider enabling S3 bucket logging for audit trails
- Review and restrict access to DynamoDB lock table

## Additional Resources

- [Terraform S3 Backend Documentation](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [AWS Organizations Best Practices](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices.html)
- [AWS Control Tower Documentation](https://docs.aws.amazon.com/controltower/)

## Support

For issues or questions:
1. Check individual module README files
2. Review Terraform and AWS documentation
3. Check CloudWatch logs for AWS service errors
4. Verify IAM permissions and AWS service quotas
