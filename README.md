![Bose Professional](./images/boseprofessional.png)

# AWS Developer Accounts

Automated AWS account provisioning and infrastructure management for developer sandbox environments.

## Overview

This project provides a complete Terraform-based solution for creating and managing isolated AWS developer accounts with built-in cost controls, security boundaries, and infrastructure modules. It enables developers to experiment and build applications in secure, budget-controlled environments.

## Features

- **Automated Account Provisioning**: Create AWS accounts via Organizations with a single Terraform command
- **Cost Controls**: $100/month budget limits with automated alerts and resource termination
- **Security Boundaries**: IAM permission boundaries prevent privilege escalation and restrict expensive resources
- **Infrastructure as Code**: Complete set of Terraform modules for common AWS services
- **Cross-Platform Support**: Works on Windows (PowerShell), macOS, and Linux
- **Self-Service Ready**: Designed for future self-service portal integration

## Project Status

**Current Release**: Rank 1 Complete (October 2024)

### Available Modules

| Module | Status | Description |
|--------|--------|-------------|
| Account Factory | Complete | Automated AWS account provisioning |
| VPC Networking | Complete | Multi-AZ VPC with public/private/database subnets |
| Security Groups | Complete | Pre-configured security group patterns |
| Application Load Balancer | Complete | ALB with SSL, routing, and health checks |
| ECS Service | Complete | Fargate-based container orchestration |
| ECR | Complete | Container registry with scanning |
| EC2 | Complete | Cost-optimized compute instances |
| RDS PostgreSQL | Complete | Managed database with backups |
| S3 | Complete | Object storage with encryption |
| API Gateway | Complete | HTTP/REST API management |
| Secrets Manager | Complete | Secure credential storage |

### Coming Soon

- Lambda (Serverless compute)
- EventBridge (Event-driven architecture)
- DynamoDB (NoSQL database)
- SNS/SQS (Messaging)

## Prerequisites

### Required Tools

- **Terraform** >= 1.5.0
- **AWS CLI** >= 2.x
- **jq** (JSON processor)
- **Git**

### AWS Requirements

- AWS Organizations enabled in management account
- IAM permissions for:
  - `organizations:*` (account creation)
  - `iam:*` (role/policy management)
  - `sts:AssumeRole` (cross-account access)
  - `s3:*`, `dynamodb:*` (state management)
  - `budgets:*` (cost controls)

### Installation

#### Windows (PowerShell)
```powershell
# Install Chocolatey (if not already installed)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install tools
choco install terraform awscli jq git -y

# Verify installations
terraform version
aws --version
jq --version
```

#### macOS
```bash
brew install terraform awscli jq git
# Optional: tfswitch for managing multiple Terraform versions
brew install tfswitch
```

#### Linux (Ubuntu/Debian)
```bash
# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# AWS CLI, jq, and Git
sudo apt install awscli jq git
```

## Quick Start

### 1. Clone Repository

**Bash/Linux/Mac:**
```bash
git clone https://github.com/bose/aws-developer-accounts.git
cd aws-developer-accounts
```

**PowerShell:**
```powershell
git clone https://github.com/bose/aws-developer-accounts.git
cd aws-developer-accounts
```

### 2. Configure AWS Credentials

**For AWS SSO (Recommended):**

**Bash/Linux/Mac:**
```bash
aws configure sso
# Follow prompts to configure SSO

# Login
aws sso login --profile your-profile-name

# Set as active profile (REQUIRED for Terraform)
export AWS_PROFILE=your-profile-name
export TF_VAR_aws_profile=$AWS_PROFILE
```

**PowerShell:**
```powershell
aws configure sso
# Follow prompts to configure SSO

# Login
aws sso login --profile your-profile-name

# Set as active profile (REQUIRED for Terraform)
$env:AWS_PROFILE = "your-profile-name"
$env:TF_VAR_aws_profile = $env:AWS_PROFILE
```

**For IAM User Credentials:**

**Bash/Linux/Mac:**
```bash
aws configure
# Enter your management account credentials

# Set as active profile (REQUIRED for Terraform)
export AWS_PROFILE=default
export TF_VAR_aws_profile=$AWS_PROFILE
```

**PowerShell:**
```powershell
aws configure
# Enter your management account credentials

# Set as active profile (REQUIRED for Terraform)
$env:AWS_PROFILE = "default"
$env:TF_VAR_aws_profile = $env:AWS_PROFILE
```

> **Note:** You must set BOTH environment variables on all platforms. The first tells AWS CLI which profile to use, the second passes it to Terraform as a variable.

### 3. Create a Developer Account

**Bash/Linux/Mac:**
```bash
# Navigate to test directory (to separate test scenarios between developers)
cd tests/unit/modules/account-factory-test-1

# Review and customize main.tf
vim main.tf

# Set your AWS profile (BOTH variables required!)
export AWS_PROFILE=your-profile-name
export TF_VAR_aws_profile=$AWS_PROFILE

# Verify variables are set
echo "AWS_PROFILE: $AWS_PROFILE"
echo "TF_VAR_aws_profile: $TF_VAR_aws_profile"

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Create the account
terraform apply
```

**PowerShell:**
```powershell
# Navigate to test directory (to separate test scenarios between developers)
cd tests/unit/modules/account-factory-test-1

# Review and customize main.tf
notepad main.tf

# Set your AWS profile (BOTH variables required!)
$env:AWS_PROFILE = "your-profile-name"
$env:TF_VAR_aws_profile = $env:AWS_PROFILE

# Verify variables are set
Write-Host "AWS_PROFILE: $env:AWS_PROFILE"
Write-Host "TF_VAR_aws_profile: $env:TF_VAR_aws_profile"

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Create the account
terraform apply
```

> **Important:** Setting `TF_VAR_aws_profile` is required on all platforms because the account factory module passes the AWS profile to provisioner scripts. Without it, you'll get "config profile () could not be found" errors.

### 4. Access Your New Account

**Bash/Linux/Mac:**
```bash
# Get account ID from Terraform output
ACCOUNT_ID=$(terraform output -raw account_id)

# Configure AWS CLI profile
aws configure set profile.your-name role_arn arn:aws:iam::$ACCOUNT_ID:role/DeveloperRole
aws configure set profile.your-name source_profile default
aws configure set profile.your-name region us-west-2

# Test access
aws sts get-caller-identity --profile your-name
```

**PowerShell:**
```powershell
# Get account ID from Terraform output
$ACCOUNT_ID = terraform output -raw account_id

# Configure AWS CLI profile
aws configure set profile.your-name role_arn "arn:aws:iam::$ACCOUNT_ID:role/DeveloperRole"
aws configure set profile.your-name source_profile default
aws configure set profile.your-name region us-west-2

# Test access
aws sts get-caller-identity --profile your-name
```

### 5. Deploy Infrastructure

**Bash/Linux/Mac:**
```bash
# Review the generated backend configuration
cd generated/your-name/
cat backend.tf

# Start building with modules
terraform init
terraform plan
```

**PowerShell:**
```powershell
# Review the generated backend configuration
cd generated/your-name/
Get-Content backend.tf

# Start building with modules
terraform init
terraform plan
```

## Architecture

```
Management Account
    │
    ├── Account Factory (Terraform)
    │   ├── Creates Member Account
    │   ├── Sets up IAM Roles
    │   ├── Configures Budgets
    │   └── Creates Base Infrastructure
    │
    └── Developer Accounts
        ├── bose-dev-developer-1
        │   ├── S3 State Bucket
        │   ├── DynamoDB Lock Table
        │   ├── IAM Permission Boundary
        │   ├── DeveloperRole
        │   └── Budget ($100/month)
        │
        └── bose-dev-developer-2
            └── (same structure)
```

## Directory Structure

```
aws-developer-accounts/
├── modules/              # Reusable Terraform modules
│   ├── account-factory/  # Account provisioning
│   ├── networking/       # VPC, Security Groups, ALB
│   ├── compute/         # EC2
│   ├── containers/      # ECS, ECR
│   ├── databases/       # RDS
│   ├── storage/         # S3
│   ├── api/            # API Gateway
│   └── security/       # Secrets Manager
│
├── environments/        # Environment configurations
│   ├── dev-accounts/   # Developer account definitions
│   ├── fusion-dev/     # Shared dev environment
│   └── fusion-staging/ # Shared staging environment
│
├── templates/          # Application patterns
│   └── application-patterns/
│       ├── web-application/
│       ├── serverless-api/
│       └── microservices/
│
├── tests/             # Test configurations
│   └── unit/modules/
│
├── docs/              # Documentation
│   ├── architecture/
│   ├── developer-guide/
│   └── operations/
│
└── scripts/           # Automation scripts
    ├── setup/
    ├── validation/
    └── utilities/
```

## Cost Management

### Budget Enforcement

Each developer account has:
- **$100/month hard cap** with automatic resource termination
- **80% threshold** alert (email to developer + infrastructure team)
- **90% forecast** alert (proactive warning)

### Cost Optimization Tips

1. Use approved instance types only (t3/t4g micro, small, medium)
2. Enable auto-scaling for ECS services
3. Use single NAT Gateway (not multi-AZ) for development
4. Stop/terminate resources when not in use
5. Set S3 lifecycle policies to transition to cheaper storage

### Monitoring Costs

#### View Current Month Spend

**Bash/Linux/Mac:**
```bash
# Get current month spend
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost UnblendedCost \
  --profile your-name \
  --output table
```

**PowerShell:**
```powershell
# Get current month spend
$StartDate = (Get-Date -Day 1).ToString("yyyy-MM-dd")
$EndDate = (Get-Date).ToString("yyyy-MM-dd")

aws ce get-cost-and-usage `
  --time-period Start=$StartDate,End=$EndDate `
  --granularity MONTHLY `
  --metrics BlendedCost UnblendedCost `
  --profile your-name `
  --output table
```

#### View Daily Costs (Last 30 Days)

**Bash/Linux/Mac:**
```bash
# Daily breakdown for last 30 days
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --profile your-name \
  --output table
```

**PowerShell:**
```powershell
# Daily breakdown for last 30 days
$StartDate = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")
$EndDate = (Get-Date).ToString("yyyy-MM-dd")

aws ce get-cost-and-usage `
  --time-period Start=$StartDate,End=$EndDate `
  --granularity DAILY `
  --metrics BlendedCost `
  --profile your-name `
  --output table
```

#### View Costs by Service

**Bash/Linux/Mac:**
```bash
# Break down costs by AWS service
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --profile your-name \
  --output table
```

**PowerShell:**
```powershell
# Break down costs by AWS service
$StartDate = (Get-Date -Day 1).ToString("yyyy-MM-dd")
$EndDate = (Get-Date).ToString("yyyy-MM-dd")

aws ce get-cost-and-usage `
  --time-period Start=$StartDate,End=$EndDate `
  --granularity MONTHLY `
  --metrics BlendedCost `
  --group-by Type=DIMENSION,Key=SERVICE `
  --profile your-name `
  --output table
```

#### Check Budget Status

**Bash/Linux/Mac:**
```bash
# Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile your-name --query Account --output text)

# Check budget details
aws budgets describe-budgets \
  --account-id $ACCOUNT_ID \
  --profile your-name
```

**PowerShell:**
```powershell
# Get your account ID
$ACCOUNT_ID = aws sts get-caller-identity --profile your-name --query Account --output text

# Check budget details
aws budgets describe-budgets `
  --account-id $ACCOUNT_ID `
  --profile your-name
```

#### Forecast Next Month's Costs

**Bash/Linux/Mac:**
```bash
# Get cost forecast for next 30 days
NEXT_MONTH_START=$(date -d '1 month' +%Y-%m-01)
NEXT_MONTH_END=$(date -d "$NEXT_MONTH_START +1 month -1 day" +%Y-%m-%d)

aws ce get-cost-forecast \
  --time-period Start=$NEXT_MONTH_START,End=$NEXT_MONTH_END \
  --metric BLENDED_COST \
  --granularity MONTHLY \
  --profile your-name
```

**PowerShell:**
```powershell
# Get cost forecast for next 30 days
$NextMonthStart = (Get-Date).AddMonths(1)
$NextMonthStart = Get-Date -Year $NextMonthStart.Year -Month $NextMonthStart.Month -Day 1
$NextMonthEnd = $NextMonthStart.AddMonths(1).AddDays(-1)

aws ce get-cost-forecast `
  --time-period Start=$($NextMonthStart.ToString("yyyy-MM-dd")),End=$($NextMonthEnd.ToString("yyyy-MM-dd")) `
  --metric BLENDED_COST `
  --granularity MONTHLY `
  --profile your-name
```

#### Create Cost Alert Dashboard (Script)

**Bash/Linux/Mac:**
Create `scripts/cost-dashboard.sh`:
```bash
#!/bin/bash
PROFILE=${1:-default}

echo "================================"
echo "AWS Cost Dashboard"
echo "Profile: $PROFILE"
echo "================================"
echo ""

# Current spend
echo "Current Month Spend:"
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --profile $PROFILE \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
  --output text | xargs printf "$%.2f\n"

echo ""

# Top 5 services by cost
echo "Top 5 Services by Cost:"
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --profile $PROFILE \
  --query 'ResultsByTime[0].Groups[?Metrics.BlendedCost.Amount>`0`]|[0:5].[Keys[0],Metrics.BlendedCost.Amount]' \
  --output table
```

**PowerShell:**
Create `scripts/cost-dashboard.ps1`:
```powershell
param(
    [string]$Profile = "default"
)

Write-Host "================================" -ForegroundColor Cyan
Write-Host "AWS Cost Dashboard" -ForegroundColor Cyan
Write-Host "Profile: $Profile" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Current spend
Write-Host "Current Month Spend:" -ForegroundColor Yellow
$StartDate = (Get-Date -Day 1).ToString("yyyy-MM-dd")
$EndDate = (Get-Date).ToString("yyyy-MM-dd")

$Cost = aws ce get-cost-and-usage `
  --time-period Start=$StartDate,End=$EndDate `
  --granularity MONTHLY `
  --metrics BlendedCost `
  --profile $Profile `
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' `
  --output text

Write-Host "`$$([math]::Round($Cost, 2))" -ForegroundColor Green
Write-Host ""

# Top 5 services by cost
Write-Host "Top 5 Services by Cost:" -ForegroundColor Yellow
aws ce get-cost-and-usage `
  --time-period Start=$StartDate,End=$EndDate `
  --granularity MONTHLY `
  --metrics BlendedCost `
  --group-by Type=DIMENSION,Key=SERVICE `
  --profile $Profile `
  --query 'ResultsByTime[0].Groups[?Metrics.BlendedCost.Amount>`0`]|[0:5].[Keys[0],Metrics.BlendedCost.Amount]' `
  --output table
```

#### List Running Resources (Cost Contributors)

**Bash/Linux/Mac:**
```bash
# List all running EC2 instances
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,State:State.Name,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table \
  --profile your-name

# List all RDS databases
aws rds describe-db-instances \
  --query 'DBInstances[].{ID:DBInstanceIdentifier,Engine:Engine,Class:DBInstanceClass,Status:DBInstanceStatus}' \
  --output table \
  --profile your-name

# List all ALBs
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[].{Name:LoadBalancerName,Type:Type,State:State.Code}' \
  --output table \
  --profile your-name
```

**PowerShell:**
```powershell
# List all running EC2 instances
Write-Host "Running EC2 Instances:" -ForegroundColor Yellow
aws ec2 describe-instances `
  --filters "Name=instance-state-name,Values=running" `
  --query 'Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,State:State.Name,Name:Tags[?Key==`Name`]|[0].Value}' `
  --output table `
  --profile your-name

# List all RDS databases
Write-Host "`nRDS Databases:" -ForegroundColor Yellow
aws rds describe-db-instances `
  --query 'DBInstances[].{ID:DBInstanceIdentifier,Engine:Engine,Class:DBInstanceClass,Status:DBInstanceStatus}' `
  --output table `
  --profile your-name

# List all ALBs
Write-Host "`nLoad Balancers:" -ForegroundColor Yellow
aws elbv2 describe-load-balancers `
  --query 'LoadBalancers[].{Name:LoadBalancerName,Type:Type,State:State.Code}' `
  --output table `
  --profile your-name
```

## Security

### Built-in Security Features

- **Encryption at rest** (S3, RDS, EBS)
- **Encryption in transit** (TLS/SSL enforced)
- **IAM permission boundaries** (prevent privilege escalation)
- **Network isolation** (VPC with private subnets)
- **Secrets management** (no hardcoded credentials)
- **Container scanning** (ECR vulnerability detection)
- **Access logging** (CloudTrail, VPC Flow Logs)

### Service Control Policies

Developers **cannot**:
- Access AWS Marketplace
- Launch expensive instance types (> t3.medium)
- Modify billing settings
- Access AWS Organizations
- Deploy outside approved regions

Developers **can**:
- Create EC2, ECS, Lambda, RDS, S3, DynamoDB
- Create IAM roles (with permission boundaries)
- Access CloudWatch logs and metrics
- Deploy in us-east-1 and us-west-2

## Troubleshooting

### Common Issues

#### "The config profile () could not be found"

This happens when Terraform provisioner scripts don't have access to your AWS profile.

**Solution - Bash/Linux/Mac:**
```bash
# You must set BOTH environment variables
export AWS_PROFILE=your-profile-name
export TF_VAR_aws_profile=$AWS_PROFILE

# Verify they're set
echo "AWS_PROFILE: $AWS_PROFILE"
echo "TF_VAR_aws_profile: $TF_VAR_aws_profile"

# Then run Terraform
terraform apply
```

**Solution - PowerShell:**
```powershell
# You must set BOTH environment variables
$env:AWS_PROFILE = "your-profile-name"
$env:TF_VAR_aws_profile = $env:AWS_PROFILE

# Verify they're set
Write-Host "AWS_PROFILE: $env:AWS_PROFILE"
Write-Host "TF_VAR_aws_profile: $env:TF_VAR_aws_profile"

# Then run Terraform
terraform apply
```

**Why both?**
- `AWS_PROFILE` / `$env:AWS_PROFILE` - Used by AWS CLI and Terraform provider
- `TF_VAR_aws_profile` / `$env:TF_VAR_aws_profile` - Passed to the account-factory module, which passes it to shell scripts

**Make it permanent (optional):**

**Bash/Linux/Mac:**
```bash
# Add to ~/.bashrc or ~/.zshrc
echo 'export AWS_PROFILE=your-profile-name' >> ~/.bashrc
echo 'export TF_VAR_aws_profile=$AWS_PROFILE' >> ~/.bashrc
source ~/.bashrc
```

**PowerShell:**
```powershell
# Add to your PowerShell profile
Add-Content $PROFILE "`n`$env:AWS_PROFILE='your-profile-name'"
Add-Content $PROFILE "`$env:TF_VAR_aws_profile=`$env:AWS_PROFILE"
```

#### "Access Denied" when running AWS CLI

**Check your profile:**
```bash
# Bash
echo $AWS_PROFILE

# PowerShell
echo $env:AWS_PROFILE
```

**Verify credentials:**
```bash
aws sts get-caller-identity --profile your-name
```

#### Terraform state lock errors

**Bash/Linux/Mac:**
```bash
# List locks
aws dynamodb scan \
  --table-name your-terraform-locks-table \
  --profile your-name

# Force unlock (use with caution!)
terraform force-unlock <LOCK_ID>
```

**PowerShell:**
```powershell
# List locks
aws dynamodb scan `
  --table-name your-terraform-locks-table `
  --profile your-name

# Force unlock (use with caution!)
terraform force-unlock <LOCK_ID>
```

## Support

### Documentation
- [Architecture Overview](docs/architecture/)
- [Developer Guide](docs/developer-guide/)
- [Troubleshooting Guide](docs/developer-guide/troubleshooting.md)
- [Best Practices](docs/developer-guide/best-practices.md)

### Getting Help
- **Questions**: infrastructure-team@bose.com
- **Issues**: Create Jira ticket in INFRA project
- **Wiki**: [Internal Documentation](https://wiki.bose.com/aws-accounts)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Adding new modules
- Testing requirements
- Code standards
- Pull request process

## License

Copyright © 2025 Bose Professional Corporation. All rights reserved.

### See [LICENSE](LICENSE) for details.
