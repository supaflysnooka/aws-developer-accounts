# Terraform Backend Bootstrap

This module creates the foundational infrastructure for Terraform remote state management using AWS S3 and DynamoDB.

## Purpose

Creates and configures:
- **S3 Bucket** - Stores Terraform state files with versioning and encryption
- **DynamoDB Table** - Provides state locking and consistency checking

This module uses **local state** during initial deployment since the backend doesn't exist yet. After creation, you can optionally migrate this module to use the remote backend it creates.

## Architecture

```
┌─────────────────────────────────────────┐
│         S3 Bucket                       │
│  ┌───────────────────────────────────┐  │
│  │   Terraform State Files           │  │
│  │   • Versioned                     │  │
│  │   • Encrypted (AES256)            │  │
│  │   • Private (no public access)    │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
                    │
                    │ State Operations
                    ▼
┌─────────────────────────────────────────┐
│      DynamoDB Table                     │
│  ┌───────────────────────────────────┐  │
│  │   State Locks                     │  │
│  │   • Hash Key: LockID              │  │
│  │   • Pay-per-request billing       │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## Features

### S3 Bucket Configuration
- **Versioning enabled** - Recover from accidental deletions or corruption
- **Server-side encryption** - AES256 encryption with bucket keys for cost optimization
- **Public access blocked** - All four public access block settings enabled
- **Lifecycle policies**:
  - Delete non-current versions after 90 days
  - Abort incomplete multipart uploads after 7 days
- **Lifecycle protection** - `prevent_destroy` enabled

### DynamoDB Table Configuration
- **Pay-per-request billing** - No capacity planning needed
- **State locking** - Prevents concurrent state modifications
- **Simple schema** - Single hash key (LockID)
- **Lifecycle protection** - `prevent_destroy` enabled

## Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.5.0
- AWS permissions to create:
  - S3 buckets
  - DynamoDB tables
- A globally unique S3 bucket name

## Usage

### Initial Deployment

1. **Choose a unique bucket name** (S3 bucket names must be globally unique):
```bash
# Good naming pattern: <org>-<env>-terraform-state
# Example: acme-prod-terraform-state
```

2. **Create a terraform.tfvars file**:
```hcl
region            = "us-west-2"
state_bucket_name = "your-unique-bucket-name"
lock_table_name   = "terraform-state-locks"
```

3. **Initialize and deploy**:
```bash
terraform init
terraform plan
terraform apply
```

4. **Save the outputs** - You'll need these for configuring backends in other modules:
```bash
terraform output backend_config > ../backend-config.txt
```

### Example Outputs

After successful deployment:

```
state_bucket_name = "acme-prod-terraform-state"
state_bucket_arn = "arn:aws:s3:::acme-prod-terraform-state"
lock_table_name = "terraform-state-locks"
lock_table_arn = "arn:aws:dynamodb:us-west-2:123456789012:table/terraform-state-locks"

backend_config = <<EOT
backend "s3" {
  bucket         = "acme-prod-terraform-state"
  key            = "path/to/terraform.tfstate"
  region         = "us-west-2"
  dynamodb_table = "terraform-state-locks"
  encrypt        = true
}
EOT
```

## Migrating to Remote State (Optional)

After the initial deployment, you can migrate this module itself to use the remote backend:

1. **Add backend configuration to `main.tf`**:
```hcl
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "your-bucket-name"
    key            = "bootstrap/terraform-backend/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
```

2. **Migrate the state**:
```bash
terraform init -migrate-state
```

3. **Verify migration**:
```bash
# Check that state is in S3
aws s3 ls s3://your-bucket-name/bootstrap/terraform-backend/

# Local state file should now be empty/minimal
cat terraform.tfstate
```

4. **Backup and remove local state** (optional):
```bash
# Backup local state
cp terraform.tfstate terraform.tfstate.local.backup

# The local file is no longer used after migration
```

## Using the Backend in Other Modules

In other Terraform projects, configure the backend block:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-bucket-name"
    key            = "production/vpc/terraform.tfstate"  # Unique per project
    region         = "us-west-2"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
```

### State File Organization

Recommended key structure for different modules:
```
bootstrap/terraform-backend/terraform.tfstate
bootstrap/organization/terraform.tfstate
bootstrap/control-tower/terraform.tfstate
production/vpc/terraform.tfstate
production/eks/terraform.tfstate
staging/vpc/terraform.tfstate
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| region | AWS region for resources | string | us-west-2 | no |
| state_bucket_name | S3 bucket name for state | string | n/a | yes |
| lock_table_name | DynamoDB table name for locks | string | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| state_bucket_name | Name of the S3 bucket |
| state_bucket_arn | ARN of the S3 bucket |
| lock_table_name | Name of the DynamoDB table |
| lock_table_arn | ARN of the DynamoDB table |
| backend_config | Ready-to-use backend configuration block |

## Cost Estimation

### S3 Costs
- Storage: ~$0.023 per GB per month (Standard tier)
- Requests: Minimal for state operations
- Versioning: Additional storage for old versions (90-day retention)

**Estimated monthly cost**: $0.10 - $1.00 for typical usage

### DynamoDB Costs
- Pay-per-request: $1.25 per million write requests, $0.25 per million read requests
- Storage: $0.25 per GB per month

**Estimated monthly cost**: $0.01 - $0.10 for typical usage

**Total estimated monthly cost**: $0.11 - $1.10

## Security Best Practices

### Implemented
- Encryption at rest (S3 and DynamoDB)
- Encryption in transit (AWS SDK uses HTTPS)
- Versioning enabled for recovery
- Public access blocked
- Lifecycle protection on critical resources

### Recommended Additional Steps

1. **Enable S3 bucket logging**:
```hcl
resource "aws_s3_bucket_logging" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "terraform-state-logs/"
}
```

2. **Add bucket policy for restricted access**:
```hcl
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
```

3. **Enable MFA delete** (requires root account):
```bash
aws s3api put-bucket-versioning \
  --bucket your-bucket-name \
  --versioning-configuration Status=Enabled,MFADelete=Enabled \
  --mfa "arn:aws:iam::123456789012:mfa/root-account-mfa-device XXXXXX"
```

4. **Restrict IAM access**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::your-bucket-name",
        "arn:aws:s3:::your-bucket-name/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:us-west-2:123456789012:table/terraform-state-locks"
    }
  ]
}
```

## Troubleshooting

### Bucket Name Already Exists
```
Error: creating S3 Bucket: BucketAlreadyExists
```
**Solution**: S3 bucket names are globally unique. Choose a different name.

### State Lock Timeout
```
Error: Error acquiring the state lock
```
**Solution**: 
```bash
# View locks
aws dynamodb scan --table-name terraform-state-locks

# Force unlock (use cautiously)
terraform force-unlock <LOCK_ID>
```

### Insufficient Permissions
```
Error: creating S3 Bucket: AccessDenied
```
**Solution**: Ensure IAM user/role has permissions:
- `s3:CreateBucket`
- `s3:PutBucketVersioning`
- `s3:PutEncryptionConfiguration`
- `s3:PutBucketPublicAccessBlock`
- `dynamodb:CreateTable`

### Can't Destroy Resources
```
Error: Instance cannot be destroyed
```
**Solution**: Resources have `prevent_destroy` lifecycle rule. To destroy:
1. Remove lifecycle block from resource
2. Apply changes
3. Run `terraform destroy`

## State Recovery

### Recovering from Accidental Deletion

List available versions:
```bash
aws s3api list-object-versions \
  --bucket your-bucket-name \
  --prefix bootstrap/terraform-backend/terraform.tfstate
```

Restore a specific version:
```bash
aws s3api copy-object \
  --bucket your-bucket-name \
  --copy-source your-bucket-name/bootstrap/terraform-backend/terraform.tfstate?versionId=VERSION_ID \
  --key bootstrap/terraform-backend/terraform.tfstate
```

### Recovering from Corrupted State

1. Download the latest valid version from S3
2. Manually inspect and repair if needed
3. Force unlock if necessary
4. Push corrected state back

## Maintenance Tasks

### Regular Reviews
- Review DynamoDB for stale locks (shouldn't exist for long periods)
- Check S3 bucket size and version count
- Audit IAM access policies quarterly
- Review CloudTrail logs for unauthorized access attempts

### Updating Lifecycle Policies

To change version retention from 90 to 180 days:
```hcl
noncurrent_version_expiration {
  noncurrent_days = 180
}
```

Then apply:
```bash
terraform apply
```

## Related Documentation

- [Terraform Backend Configuration](https://developer.hashicorp.com/terraform/language/settings/backends/configuration)
- [S3 Backend Documentation](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [AWS S3 Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
