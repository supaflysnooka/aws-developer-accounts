# Developer Guide

Complete guide for developers using the AWS developer accounts system.

## Table of Contents

- [Getting Started](#getting-started)
- [Account Access](#account-access)
- [Using Terraform Modules](#using-terraform-modules)
- [Common Patterns](#common-patterns)
- [Cost Management](#cost-management)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Getting Started

### Prerequisites

Before you begin, ensure you have:
- [ ] Developer account created by infrastructure team
- [ ] AWS CLI installed and configured
- [ ] Terraform >= 1.5.0 installed
- [ ] Access to your account's onboarding documentation

### Initial Setup

1. **Locate your onboarding documentation:**
```bash
# Infrastructure team will provide this path
cat generated/your-name/onboarding.md
```

2. **Configure AWS CLI profile:**
```bash
# Replace YOUR_NAME and ACCOUNT_ID with your actual values
aws configure set profile.YOUR_NAME role_arn arn:aws:iam::ACCOUNT_ID:role/DeveloperRole
aws configure set profile.YOUR_NAME source_profile default
aws configure set profile.YOUR_NAME region us-east-1
```

3. **Test access:**
```bash
aws sts get-caller-identity --profile YOUR_NAME

# Expected output:
# {
#     "UserId": "AROA...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:sts::123456789012:assumed-role/DeveloperRole/..."
# }
```

4. **Set default profile (optional):**
```bash
export AWS_PROFILE=YOUR_NAME
# Add to ~/.bashrc or ~/.zshrc to persist
```

## Account Access

### Assuming the DeveloperRole

Your account access uses AWS IAM role assumption. Here's how it works:

```
Your Management Account Credentials
    ↓ (sts:AssumeRole)
DeveloperRole in Your Account
    ↓ (with PowerUserAccess + Permission Boundary)
Access to AWS Services
```

### Manual Role Assumption

If you need temporary credentials directly:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/DeveloperRole \
  --role-session-name my-session \
  --duration-seconds 3600

# Export the credentials
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

### Session Duration

- Default: 1 hour
- Maximum: 12 hours
- Auto-refresh with AWS CLI profiles

## Using Terraform Modules

### Backend Configuration

Your account has a pre-configured S3 backend for Terraform state:

```hcl
# backend.tf (generated for you)
terraform {
  backend "s3" {
    bucket         = "bose-dev-YOUR_NAME-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "bose-dev-YOUR_NAME-terraform-locks"
    encrypt        = true
  }
}
```

### Module Usage

All modules are located in the `modules/` directory. Example:

```hcl
# main.tf
module "my_vpc" {
  source = "git::https://github.com/bose/aws-developer-accounts.git//modules/networking/vpc"
  
  vpc_name           = "my-app-vpc"
  vpc_cidr          = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
}

output "vpc_id" {
  value = module.my_vpc.vpc_id
}
```

### Standard Workflow

```bash
# 1. Initialize (first time or when adding providers/modules)
terraform init

# 2. Validate syntax
terraform validate

# 3. Format code
terraform fmt

# 4. Plan changes
terraform plan -out=tfplan

# 5. Review plan carefully
terraform show tfplan

# 6. Apply changes
terraform apply tfplan

# 7. View outputs
terraform output
```

## Common Patterns

### Pattern 1: Simple Web Application

```hcl
# VPC + ALB + ECS + RDS
module "vpc" {
  source = "../../modules/networking/vpc"
  
  vpc_name           = "webapp-vpc"
  vpc_cidr          = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
}

module "security_groups" {
  source = "../../modules/networking/security-groups"
  
  name_prefix = "webapp"
  vpc_id      = module.vpc.vpc_id
  
  create_web_alb_sg      = true
  create_web_backend_sg  = true
  create_database_sg     = true
}

module "alb" {
  source = "../../modules/networking/alb"
  
  alb_name           = "webapp-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnets
  security_group_ids = [module.security_groups.web_alb_security_group_id]
}

module "ecs" {
  source = "../../modules/containers/ecs-service"
  
  cluster_name    = "webapp-cluster"
  service_name    = "webapp"
  container_image = "nginx:latest"
  container_port  = 80
  
  vpc_id           = module.vpc.vpc_id
  subnet_ids       = module.vpc.private_subnets
  target_group_arn = module.alb.default_target_group_arn
}

module "database" {
  source = "../../modules/databases/rds"
  
  db_name    = "webapp"
  db_username = "admin"
  
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.micro"
  
  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.security_groups.database_security_group_id]
  
  manage_master_user_password = true
}
```

### Pattern 2: Serverless API

```hcl
# API Gateway + Lambda + DynamoDB
module "api" {
  source = "../../modules/api/api-gateway"
  
  api_name = "my-api"
  api_type = "http"
  
  enable_cors        = true
  cors_allow_origins = ["*"]
}

# Lambda module coming in Rank 2

module "dynamodb" {
  source = "../../modules/databases/dynamodb"
  
  table_name = "my-data"
  hash_key   = "id"
}
```

### Pattern 3: Static Website

```hcl
# S3 + CloudFront
module "website" {
  source = "../../modules/storage/s3"
  
  bucket_name = "my-website-${random_id.suffix.hex}"
  
  cors_rules = [{
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
  }]
}

# CloudFront module coming soon
```

## Cost Management

### Viewing Your Costs

```bash
# Current month spend
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --profile YOUR_NAME

# Cost by service
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --profile YOUR_NAME
```

### Budget Alerts

You'll receive emails when:
- **80% of budget** ($80): Take action to optimize
- **90% forecast**: You're projected to exceed budget
- **100% of budget** ($100): Resources may be terminated

### Cost Optimization Checklist

- [ ] Stop EC2 instances when not in use
- [ ] Use t3/t4g instance types (lower cost)
- [ ] Enable ECS auto-scaling with low minimums
- [ ] Set S3 lifecycle policies to move old data to cheaper storage
- [ ] Delete unused EBS volumes and snapshots
- [ ] Use single NAT Gateway instead of multi-AZ (dev only)
- [ ] Clean up old CloudWatch Logs
- [ ] Delete unused ECR images

### Understanding Your Budget

Your $100/month budget includes:
- **Compute**: EC2, ECS tasks, Lambda invocations
- **Storage**: S3, EBS volumes, RDS storage
- **Data Transfer**: Outbound internet traffic, cross-region transfer
- **Networking**: NAT Gateway ($32/month), Load Balancers
- **Databases**: RDS instance hours

**Free Tier Eligible** (doesn't count toward budget):
- 750 hours/month t2.micro EC2
- 20 GB S3 storage
- 1 million Lambda requests
- Various other services

## Troubleshooting

### Common Issues

#### "Access Denied" Errors

**Problem**: Trying to perform an action outside your permission boundary.

**Solution**: Check what you're allowed to do:
- ✅ Create EC2, ECS, Lambda, S3, RDS within approved regions
- ✅ Create IAM roles with permission boundary
- ❌ Access AWS Marketplace
- ❌ Create expensive EC2 instances
- ❌ Access billing/cost management
- ❌ Modify AWS Organizations

#### "Insufficient Capacity" for EC2

**Problem**: AWS doesn't have capacity for your instance type in that AZ.

**Solution**:
```bash
# Try a different availability zone
availability_zones = ["us-east-1b", "us-east-1c"]

# Or try a different instance type
instance_type = "t4g.micro"  # ARM-based, often more available
```

#### Terraform State Lock

**Problem**: `Error acquiring the state lock`

**Solution**:
```bash
# Find the lock in DynamoDB
aws dynamodb get-item \
  --table-name bose-dev-YOUR_NAME-terraform-locks \
  --key '{"LockID":{"S":"bose-dev-YOUR_NAME-terraform-state/infrastructure/terraform.tfstate"}}' \
  --profile YOUR_NAME

# If lock is stale (> 15 minutes old), force unlock
terraform force-unlock LOCK_ID
```

#### ECS Task Won't Start

**Problem**: Task keeps stopping immediately.

**Solution**:
```bash
# Check CloudWatch logs
aws logs tail /ecs/YOUR_SERVICE --follow --profile YOUR_NAME

# Common issues:
# - Container image doesn't exist or wrong tag
# - Insufficient memory/CPU
# - Application crashes immediately
# - Missing environment variables
```

#### RDS Connection Timeout

**Problem**: Can't connect to RDS from application.

**Solution**:
```bash
# Verify security group allows access
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --profile YOUR_NAME

# Check if RDS is in private subnet (can't access from internet)
# Connect via bastion host or ECS task in same VPC

# Test connection from ECS task
aws ecs execute-command \
  --cluster YOUR_CLUSTER \
  --task YOUR_TASK_ID \
  --command "nc -zv YOUR_RDS_ENDPOINT 5432" \
  --interactive \
  --profile YOUR_NAME
```

### Getting Help

1. **Check the logs**:
   - CloudWatch Logs: `/aws/ecs/`, `/aws/lambda/`, `/aws/rds/`
   - VPC Flow Logs: Network traffic issues
   - CloudTrail: API call history

2. **Review documentation**:
   - Module READMEs in `modules/*/README.md`
   - [Troubleshooting Guide](troubleshooting.md)

3. **Ask for help**:
   - Email: infrastructure-team@bose.com
   - Jira: Create ticket in INFRA project
   - Include: Account ID, error messages, what you were trying to do

## Best Practices

### Security

1. **Never hardcode credentials**:
   ```hcl
   # ❌ BAD
   password = "MyPassword123"
   
   # ✅ GOOD
   manage_master_user_password = true  # Let AWS generate and store in Secrets Manager
   ```

2. **Use Secrets Manager**:
   ```hcl
   module "db_secret" {
     source = "../../modules/security/secrets-manager"
     
     secret_name            = "my-app-db-password"
     generate_secret_string = true
   }
   ```

3. **Enable encryption**:
   ```hcl
   # All modules enable encryption by default
   # Don't disable it unless absolutely necessary
   storage_encrypted = true  # RDS
   encrypted        = true  # EBS
   ```

4. **Use private subnets**:
   ```hcl
   # Place application in private subnets
   subnet_ids = module.vpc.private_subnets  # ✅
   
   # Not public subnets (unless it's a load balancer)
   subnet_ids = module.vpc.public_subnets   # ❌
   ```

### Infrastructure as Code

1. **Use version control**:
   ```bash
   git init
   git add .
   git commit -m "Initial infrastructure"
   git push
   ```

2. **Tag resources**:
   ```hcl
   tags = {
     Project     = "my-app"
     Environment = "dev"
     Owner       = "john-smith"
     CostCenter  = "engineering"
   }
   ```

3. **Use variables**:
   ```hcl
   # variables.tf
   variable "environment" {
     description = "Environment name"
     type        = string
     default     = "dev"
   }
   
   # main.tf
   resource "aws_instance" "app" {
     tags = {
       Name = "app-${var.environment}"
     }
   }
   ```

4. **Module versioning**:
   ```hcl
   # Pin to specific version
   module "vpc" {
     source = "git::https://github.com/bose/aws-developer-accounts.git//modules/networking/vpc?ref=v1.0.0"
   }
   ```

### Performance

1. **Use auto-scaling**:
   ```hcl
   enable_autoscaling = true
   min_capacity      = 1
   max_capacity      = 5
   ```

2. **Choose right instance sizes**:
   ```
   Dev/Test:    t3.micro  (2 vCPU, 1 GB RAM)
   Small apps:  t3.small  (2 vCPU, 2 GB RAM)
   Medium apps: t3.medium (2 vCPU, 4 GB RAM)
   ```

3. **Enable caching**:
   - CloudFront for static assets
   - ElastiCache for database queries (future module)
   - Application-level caching

### Cost Management

1. **Tag everything for cost allocation**:
   ```hcl
   tags = {
     Project = "mobile-app"
     Team    = "platform"
   }
   ```

2. **Clean up regularly**:
   ```bash
   # Find unused resources
   aws ec2 describe-volumes --filters "Name=status,Values=available" --profile YOUR_NAME
   aws ec2 describe-snapshots --owner-ids self --profile YOUR_NAME
   
   # Delete old images
   aws ecr list-images --repository-name my-app --profile YOUR_NAME
   ```

3. **Use lifecycle policies**:
   ```hcl
   lifecycle_rules = [{
     id      = "archive-old-data"
     enabled = true
     transition_to_glacier_days = 90
     expiration_days           = 365
   }]
   ```

### Development Workflow

1. **Use workspaces for multiple environments**:
   ```bash
   terraform workspace new feature-branch
   terraform workspace select feature-branch
   terraform apply
   ```

2. **Always plan before apply**:
   ```bash
   terraform plan -out=tfplan
   # Review carefully
   terraform apply tfplan
   ```

3. **Destroy when done testing**:
   ```bash
   terraform destroy
   # Saves money and keeps account clean
   ```

## Available Services

### What You Can Use

| Service | Description | Cost Estimate |
|---------|-------------|---------------|
| EC2 (t3/t4g) | Virtual servers | $3-15/month |
| ECS Fargate | Containers | $5-20/month |
| RDS (t3.micro) | Database | $15-25/month |
| S3 | Object storage | $0.023/GB/month |
| ALB | Load balancer | $16/month + data |
| NAT Gateway | Private subnet internet | $32/month + data |
| CloudWatch | Monitoring | $0.50/GB logs |
| Lambda | Serverless (Rank 2) | $0.20/million requests |

### What You Cannot Use

- AWS Marketplace (blocked)
- Expensive instances (m5, c5, r5, etc.)
- GPU instances (p3, g4)
- Reserved/Savings Plans (billing access blocked)
- AWS Support plans (org-level only)

## Code Examples

### Example 1: Complete Web App

See `templates/application-patterns/web-application/` for a complete example including:
- VPC with public/private subnets
- Application Load Balancer
- ECS service with auto-scaling
- RDS PostgreSQL database
- S3 bucket for assets
- All security groups configured

### Example 2: API Backend

See `templates/application-patterns/serverless-api/` for:
- API Gateway HTTP API
- Lambda functions (Rank 2)
- DynamoDB tables
- CloudWatch logs

### Example 3: Static Website

See `templates/application-patterns/static-website/` for:
- S3 bucket with website hosting
- CloudFront distribution
- Route53 DNS (if you have a domain)

## Next Steps

1. **Deploy your first application**:
   - Start with a simple VPC
   - Add an ECS service with nginx
   - Access via ALB

2. **Learn the modules**:
   - Read each module's README
   - Try the examples
   - Experiment safely

3. **Build something real**:
   - Use application patterns as templates
   - Adapt to your needs
   - Deploy incrementally

4. **Share feedback**:
   - What works well?
   - What's confusing?
   - What's missing?

## Quick Reference

### Essential Commands

```bash
# Assume role
export AWS_PROFILE=YOUR_NAME

# Check identity
aws sts get-caller-identity

# Initialize Terraform
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply

# Show outputs
terraform output

# Destroy everything
terraform destroy

# Check costs
aws ce get-cost-and-usage --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) --granularity MONTHLY --metrics UnblendedCost
```

### Useful Resources

- [AWS CLI Reference](https://docs.aws.amazon.com/cli/)
- [Terraform Documentation](https://www.terraform.io/docs)
- [AWS Well-Architected](https://aws.amazon.com/architecture/well-architected/)
- Internal Wiki: [link]
- Infrastructure Team: infrastructure-team@bose.com
