# Developer Account Onboarding: rob-birdwell-e5fd81ba

## Account Details
- **Account ID**: 226437016787
- **Role ARN**: arn:aws:iam::226437016787:role/DeveloperRole
- **Monthly Budget**: $${budget_limit}
- **Terraform State Bucket**: bose-dev-rob-birdwell-e5fd81ba-terraform-state

## Getting Started

### 1. Configure AWS CLI
```bash
aws configure set profile.rob-birdwell-e5fd81ba role_arn arn:aws:iam::226437016787:role/DeveloperRole
aws configure set profile.rob-birdwell-e5fd81ba source_profile default
aws configure set profile.rob-birdwell-e5fd81ba region us-west-2
```

### 2. Test Access
```bash
aws sts get-caller-identity --profile rob-birdwell-e5fd81ba
```

### 3. Clone Template Repository
```bash
git clone <TEMPLATE_REPO_URL>
cd terraform-templates
cp backend.tf.example backend.tf
# Update backend.tf with your specific values
```

### 4. Initialize Terraform
```bash
export AWS_PROFILE=rob-birdwell-e5fd81ba
terraform init
terraform plan
```

## Available Services
- EC2 (t3/t4g instances only)
- Lambda
- ECS/EKS
- S3
- DynamoDB
- RDS
- VPC/Networking
- CloudWatch/Logging
- SQS/SNS
- AWS Marketplace (Blocked)
- Expensive instance types (Blocked)
- Billing/Organizations access (Blocked)

## Budget Monitoring
- Alerts at 80% ($${budget_limit_80})
- Forecast alerts at 90% of monthly budget
- **Resource termination at $${budget_limit}**

>**Warning:** If your spending reaches the budget limit ($${budget_limit}), non-essential resources (such as EC2 instances, RDS databases, and other compute resources) may be automatically terminated.
> You will receive notifications via email prior to any termination action, allowing you to take corrective measures or request an exception from the infrastructure team.

## Support
- Documentation: [Internal Wiki Link]
- Questions: infrastructure-team@boseprofessional.com
- Issues: Create Jira ticket in INFRA project