# Testing Guide

Comprehensive testing strategy for the aws-developer-accounts project.

## Overview

This guide covers testing approaches for:
- Individual Terraform modules (unit tests)
- Module combinations (integration tests)
- Complete workflows (end-to-end tests)
- Cost estimation and validation

## Test Structure

```
tests/
├── unit/              # Individual module tests
│   └── modules/
│       ├── account-factory/
│       ├── vpc/
│       ├── ecs/
│       └── rds/
├── integration/       # Multi-module tests
│   ├── web-app/
│   └── serverless-api/
└── fixtures/         # Test data and configurations
    └── terraform.tfvars
```

## Unit Testing

### Prerequisites

- AWS credentials configured
- Terraform >= 1.5.0
- jq installed
- Access to an AWS Organizations management account (for account-factory tests)

### Running Unit Tests

#### Test Individual Modules

```bash
# VPC Module
cd tests/unit/modules/vpc
terraform init
terraform validate
terraform plan
terraform apply -auto-approve

# Verify outputs
terraform output

# Clean up
terraform destroy -auto-approve
```

#### Account Factory Module

**⚠️ Warning**: This creates a real AWS account.

```bash
cd tests/unit/modules/account-factory

# Review test configuration
cat main.tf

# Customize if needed
vim main.tf

# Run test
terraform init
terraform plan
terraform apply

# Verify account creation
aws organizations list-accounts | grep bose-dev

# Verify resources in new account
# (Configure profile first as shown in output)
aws s3 ls --profile test-account
aws dynamodb list-tables --profile test-account
aws iam get-role --role-name DeveloperRole --profile test-account

# Clean up (account remains suspended for 90 days)
terraform destroy
```

### Unit Test Checklist

For each module, verify:

- [ ] `terraform init` succeeds
- [ ] `terraform validate` passes
- [ ] `terraform plan` shows expected resources
- [ ] `terraform apply` completes without errors
- [ ] All outputs are populated correctly
- [ ] Resources are created as expected
- [ ] `terraform destroy` removes all resources
- [ ] No residual resources remain

### Common Test Patterns

#### Pattern 1: Minimal Configuration
```hcl
# Test with minimum required variables
module "test" {
  source = "../../../../modules/networking/vpc"
  
  vpc_name           = "test-vpc"
  vpc_cidr          = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
}
```

#### Pattern 2: Full Configuration
```hcl
# Test with all options enabled
module "test" {
  source = "../../../../modules/networking/vpc"
  
  vpc_name           = "test-vpc-full"
  vpc_cidr          = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  
  enable_nat_gateway     = true
  single_nat_gateway     = false  # Multi-AZ
  enable_flow_logs       = true
  enable_dns_hostnames   = true
  map_public_ip_on_launch = true
}
```

## Integration Testing

Integration tests verify that multiple modules work together correctly.

### Web Application Stack

```bash
cd tests/integration/web-app

# This test deploys:
# - VPC
# - Security Groups
# - ALB
# - ECS Service
# - RDS Database

terraform init
terraform apply

# Test the application
ALB_DNS=$(terraform output -raw alb_dns_name)
curl -I http://$ALB_DNS

# Check database connectivity
# (from ECS task)

terraform destroy
```

### Test Scenarios

#### Scenario 1: Complete Web App
**Duration**: 15-20 minutes

**Components**:
- VPC with 6 subnets
- ALB in public subnets
- ECS in private subnets
- RDS in database subnets
- Secrets Manager for credentials

**Validation**:
```bash
# ALB is accessible
curl http://<ALB_DNS>

# ECS tasks are healthy
aws ecs describe-services --cluster test-cluster --services test-service

# Database is accessible from ECS
# (test connection from task)

# Secrets are stored correctly
aws secretsmanager get-secret-value --secret-id test-db-password
```

#### Scenario 2: Serverless API
**Duration**: 10-15 minutes

**Components**:
- API Gateway
- Lambda functions (Rank 2)
- DynamoDB table

**Validation**:
```bash
# API is accessible
API_URL=$(terraform output -raw api_url)
curl $API_URL/health

# DynamoDB table exists
aws dynamodb describe-table --table-name test-table
```

## End-to-End Testing

E2E tests simulate complete developer workflows.

### Test 1: Developer Onboarding

**Objective**: Verify a developer can be onboarded and deploy infrastructure.

**Steps**:
```bash
# 1. Create developer account
cd environments/dev-accounts
terraform apply -var="developer_name=test-dev-e2e"

# 2. Configure access
ACCOUNT_ID=$(terraform output -json | jq -r '.test_dev_e2e.account_id')
aws configure set profile.test-dev-e2e role_arn arn:aws:iam::$ACCOUNT_ID:role/DeveloperRole
aws configure set profile.test-dev-e2e source_profile default

# 3. Deploy infrastructure as developer
export AWS_PROFILE=test-dev-e2e
cd ../../templates/application-patterns/web-application
terraform init
terraform apply

# 4. Verify application
terraform output

# 5. Clean up
terraform destroy
cd ../../../environments/dev-accounts
terraform destroy -target=module.test_dev_e2e
```

**Expected Results**:
- Account created in < 5 minutes
- Developer can assume role
- Infrastructure deploys successfully
- Application is accessible
- Costs are tracked correctly

### Test 2: Budget Enforcement

**Objective**: Verify budget alerts trigger correctly.

**Steps**:
```bash
# 1. Create account with low budget
terraform apply -var="budget_limit=10"

# 2. Deploy expensive resources
terraform apply -var="instance_count=5" -var="instance_type=t3.medium"

# 3. Monitor spend
watch -n 300 'aws ce get-cost-and-usage --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) --granularity MONTHLY --metrics UnblendedCost'

# 4. Verify alerts
# Check email for 80% alert
# Check email for 90% forecast alert

# 5. Clean up
terraform destroy
```

**Expected Results**:
- Budget alerts sent at 80%
- Forecast alert sent at 90%
- Resources tracked correctly

### Test 3: Security Boundaries

**Objective**: Verify permission boundaries work correctly.

**Steps**:
```bash
export AWS_PROFILE=test-dev

# Should SUCCEED
aws ec2 run-instances --instance-type t3.micro --image-id ami-12345
aws s3 mb s3://test-bucket-12345
aws iam create-role --role-name TestRole --permissions-boundary <BOUNDARY_ARN>

# Should FAIL
aws ec2 run-instances --instance-type m5.large --image-id ami-12345
aws marketplace-catalog list-entities
aws budgets describe-budgets --account-id <ACCOUNT_ID>
aws organizations list-accounts
aws iam create-role --role-name TestRole  # No boundary
```

**Expected Results**:
- Allowed operations succeed
- Denied operations fail with AccessDenied
- Error messages are clear

## Cost Estimation

### Using Infracost

Install and configure Infracost for cost estimates:

```bash
# Install
brew install infracost  # macOS
# or
curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh

# Configure
infracost auth login

# Get cost estimate
cd tests/unit/modules/vpc
infracost breakdown --path .

# Output:
# Name                                    Monthly Qty  Unit   Monthly Cost
# aws_nat_gateway.main                              1  hours        $32.85
# aws_eip.nat                                       1  hours         $3.65
# TOTAL                                                              $36.50
```

### Manual Cost Estimation

For key resources:

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| NAT Gateway | Single | $32.85 |
| NAT Gateway | Multi-AZ (2) | $65.70 |
| ALB | Standard | $16.20 + data |
| ECS Fargate | 0.25 vCPU, 0.5 GB | ~$5-10 |
| RDS t3.micro | PostgreSQL | ~$15-20 |
| S3 | 10 GB | $0.23 |
| EBS gp3 | 20 GB | $1.60 |

## Automated Testing

### Pre-commit Hooks

Set up pre-commit hooks for validation:

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Hooks will run on commit:
# - terraform fmt
# - terraform validate
# - tfsec (security scan)
# - checkov (compliance scan)
```

### GitHub Actions

The project includes GitHub Actions workflows:

**`.github/workflows/terraform-plan.yml`**:
- Runs on pull requests
- Validates syntax
- Runs security scans
- Estimates costs
- Posts results as PR comment

**`.github/workflows/terraform-apply.yml`**:
- Runs on merge to main
- Applies infrastructure changes
- Updates state

### CI/CD Testing Checklist

- [ ] Terraform format check (`terraform fmt -check`)
- [ ] Terraform validation (`terraform validate`)
- [ ] Security scan (tfsec, checkov)
- [ ] Cost estimation (Infracost)
- [ ] Integration tests pass
- [ ] Documentation is up to date

## Test Data Management

### Using Fixtures

Create reusable test data:

```hcl
# tests/fixtures/terraform.tfvars
vpc_cidr = "10.100.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]
instance_type = "t3.micro"
```

Use in tests:
```bash
terraform plan -var-file=../../../fixtures/terraform.tfvars
```

### Cleanup

Always clean up test resources:

```bash
# Automated cleanup script
#!/bin/bash
# tests/cleanup-test-resources.sh

# Delete old test accounts
aws organizations list-accounts | \
  jq -r '.Accounts[] | select(.Name | startswith("bose-dev-test")) | .Id' | \
  while read account_id; do
    aws organizations close-account --account-id $account_id
  done

# Delete test VPCs
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=test-*" | \
  jq -r '.Vpcs[].VpcId' | \
  while read vpc_id; do
    ./delete-vpc.sh $vpc_id
  done
```

## Troubleshooting Tests

### Common Test Failures

#### Timeout Creating Resources
```bash
# Increase wait time
resource "time_sleep" "wait" {
  create_duration = "120s"  # Increase from 60s
}
```

#### State Lock Issues
```bash
# Force unlock if needed
terraform force-unlock <LOCK_ID>

# Or delete test state
rm -rf .terraform terraform.tfstate*
terraform init
```

#### Resource Already Exists
```bash
# Import existing resource
terraform import aws_s3_bucket.test test-bucket-name

# Or destroy and recreate
terraform destroy -target=aws_s3_bucket.test
terraform apply
```

### Debug Mode

Enable detailed logging:

```bash
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform.log
terraform apply

# Review logs
cat terraform.log
```

## Best Practices

### Test Isolation

- Use unique names for test resources
- Use separate AWS accounts for testing when possible
- Clean up after each test run
- Don't depend on external state

### Test Documentation

Document each test:
```markdown
# Test: VPC Creation
**Purpose**: Verify VPC module creates all required resources
**Duration**: 5 minutes
**Cost**: $0.50 (during test)
**Prerequisites**: AWS credentials
**Steps**: ...
**Expected Results**: ...
```

### Continuous Testing

- Run unit tests on every commit
- Run integration tests daily
- Run E2E tests weekly
- Monitor test costs

## Test Metrics

Track test health:

| Metric | Target | Current |
|--------|--------|---------|
| Unit test pass rate | 100% | - |
| Integration test pass rate | 95%+ | - |
| E2E test pass rate | 90%+ | - |
| Average test duration | < 15 min | - |
| Test cost per run | < $5 | - |

## Resources

- [Terraform Testing Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
- [Terratest Framework](https://terratest.gruntwork.io/)
- [Infracost Documentation](https://www.infracost.io/docs/)
- Internal CI/CD Guide: [link]
