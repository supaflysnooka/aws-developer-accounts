# modules/account-factory/templates/onboarding.md.tpl
# Developer Account Onboarding: rob-birdwell-b8e30df3

## Account Details
- **Account ID**: 385003642181
- **Role ARN**: arn:aws:iam::385003642181:role/DeveloperRole
- **Monthly Budget**: ${budget_limit}
- **Terraform State Bucket**: bose-dev-rob-birdwell-b8e30df3-terraform-state

## Getting Started

### 1. Configure AWS CLI
\`\`\`bash
aws configure set profile.rob-birdwell-b8e30df3 role_arn arn:aws:iam::385003642181:role/DeveloperRole
aws configure set profile.rob-birdwell-b8e30df3 source_profile default
aws configure set profile.rob-birdwell-b8e30df3 region us-west-2
\`\`\`

### 2. Test Access
\`\`\`bash
aws sts get-caller-identity --profile rob-birdwell-b8e30df3
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
export AWS_PROFILE=rob-birdwell-b8e30df3
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
- Alerts at 80% (${budget_limit * 0.8})
- Forecast alerts at 90%
- **Resource termination at ${budget_limit}**

## Support
- Documentation: [Internal Wiki Link]
- Questions: infrastructure-team@boseprofessional.com
- Issues: Create Jira ticket in INFRA project
