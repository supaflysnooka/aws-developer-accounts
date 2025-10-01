# AWS Developer Accounts

Automated AWS account provisioning and infrastructure management for developer sandbox environments.

## Overview

This project provides a complete Terraform-based solution for creating and managing isolated AWS developer accounts with built-in cost controls, security boundaries, and infrastructure modules. It enables developers to experiment and build applications in secure, budget-controlled environments.

## Features

- **Automated Account Provisioning**: Create AWS accounts via Organizations with a single Terraform command
- **Cost Controls**: $100/month budget limits with automated alerts and resource termination
- **Security Boundaries**: IAM permission boundaries prevent privilege escalation and restrict expensive resources
- **Infrastructure as Code**: Complete set of Terraform modules for common AWS services
- **Self-Service Ready**: Designed for future self-service portal integration

## Project Status

**Current Release**: Rank 1 Complete (October 2024)

### Available Modules

| Module | Status | Description |
|--------|--------|-------------|
| Account Factory | ✅ Complete | Automated AWS account provisioning |
| VPC Networking | ✅ Complete | Multi-AZ VPC with public/private/database subnets |
| Security Groups | ✅ Complete | Pre-configured security group patterns |
| Application Load Balancer | ✅ Complete | ALB with SSL, routing, and health checks |
| ECS Service | ✅ Complete | Fargate-based container orchestration |
| ECR | ✅ Complete | Container registry with scanning |
| EC2 | ✅ Complete | Cost-optimized compute instances |
| RDS PostgreSQL | ✅ Complete | Managed database with backups |
| S3 | ✅ Complete | Object storage with encryption |
| API Gateway | ✅ Complete | HTTP/REST API management |
| Secrets Manager | ✅ Complete | Secure credential storage |

### Coming Soon (Rank 2 - October 10, 2024)

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

#### macOS
```bash
brew install terraform awscli jq
```

#### Linux (Ubuntu/Debian)
```bash
# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# AWS CLI & jq
sudo apt install awscli jq
```

## Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/bose/aws-developer-accounts.git
cd aws-developer-accounts
```

### 2. Configure AWS Credentials
```bash
aws configure
# Enter your management account credentials
```

### 3. Create a Developer Account
```bash
cd tests/unit/modules/account-factory

# Review and customize main.tf
vim main.tf

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Create the account
terraform apply
```

### 4. Access Your New Account
```bash
# Configure AWS CLI profile
aws configure set profile.your-name role_arn arn:aws:iam::<ACCOUNT_ID>:role/DeveloperRole
aws configure set profile.your-name source_profile default

# Test access
aws sts get-caller-identity --profile your-name
```

### 5. Deploy Infrastructure
```bash
# Use the generated backend configuration
cd generated/your-name/
cat backend.tf

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

```bash
# View current spend
aws ce get-cost-and-usage \
  --time-period Start=2024-10-01,End=2024-10-31 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --profile your-name

# Check budget status
aws budgets describe-budgets \
  --account-id <ACCOUNT_ID>
```

## Security

### Built-in Security Features

- ✅ **Encryption at rest** (S3, RDS, EBS)
- ✅ **Encryption in transit** (TLS/SSL enforced)
- ✅ **IAM permission boundaries** (prevent privilege escalation)
- ✅ **Network isolation** (VPC with private subnets)
- ✅ **Secrets management** (no hardcoded credentials)
- ✅ **Container scanning** (ECR vulnerability detection)
- ✅ **Access logging** (CloudTrail, VPC Flow Logs)

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

See [LICENSE](LICENSE) for details.
=======
# aws-developer-accounts
Accounts developers can utilize as a lab/sandbox area for individual development
