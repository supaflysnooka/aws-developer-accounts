# modules/account-factory/templates/onboarding.md.tpl
# Developer Account Onboarding: ${developer_name}

## Account Details
- **Account ID**: ${account_id}
- **Role ARN**: ${role_arn}
- **Monthly Budget**: $${budget_limit}
- **Terraform State Bucket**: ${bucket_name}

## Getting Started

### 1. Configure AWS CLI
\`\`\`bash
aws configure set profile.${developer_name} role_arn ${role_arn}
aws configure set profile.${developer_name} source_profile default
aws configure set profile.${developer_name} region us-west-2
\`\`\`

### 2. Test Access
\`\`\`bash
aws sts get-caller-identity --profile ${developer_name}
\`\`\`

### 3. Clone Template Repository
\`\`\`bash
git clone <TEMPLATE_REPO_URL>
cd terraform-templates
cp backend.tf.example backend.tf
# Update backend.tf with your specific values
\`\`\`

### 4. Initialize Terraform
\`\`\`bash
export AWS_PROFILE=${developer_name}
terraform init
terraform plan
\`\`\`

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
- Alerts at 80% ($${budget_limit * 0.8})
- Forecast alerts at 90%
- **Resource termination at $${budget_limit}**

## Support
- Documentation: [Internal Wiki Link]
- Questions: infrastructure-team@boseprofessional.com
- Issues: Create Jira ticket in INFRA project
