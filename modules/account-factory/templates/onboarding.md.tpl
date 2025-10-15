# Developer Account Onboarding: ${developer_name}

## Account Details
- **Account ID**: `${account_id}`
- **Role ARN**: `${role_arn}`
- **Monthly Budget**: $${budget_limit}
- **Terraform State Bucket**: `${bucket_name}`

---

## Getting Started

### 1. Configure AWS CLI

**Bash/Linux/Mac:**
```bash
aws configure set profile.${developer_name} role_arn ${role_arn}
aws configure set profile.${developer_name} source_profile default
aws configure set profile.${developer_name} region us-west-2
```

**PowerShell:**
```powershell
aws configure set profile.${developer_name} role_arn ${role_arn}
aws configure set profile.${developer_name} source_profile default
aws configure set profile.${developer_name} region us-west-2
```

> **Note:** Replace `default` with your actual management account profile name if different.

---

### 2. Test Access

**Bash/Linux/Mac:**
```bash
aws sts get-caller-identity --profile ${developer_name}
```

**PowerShell:**
```powershell
aws sts get-caller-identity --profile ${developer_name}
```

**Expected Output:**
```json
{
    "UserId": "AROAXXXXXXXXX:session-name",
    "Account": "${account_id}",
    "Arn": "arn:aws:sts::${account_id}:assumed-role/DeveloperRole/..."
}
```

---

### 3. Set as Default Profile (Optional)

**Bash/Linux/Mac:**
```bash
export AWS_PROFILE=${developer_name}
echo 'export AWS_PROFILE=${developer_name}' >> ~/.bashrc  # Make permanent
```

**PowerShell:**
```powershell
$env:AWS_PROFILE="${developer_name}"

# Make permanent (add to PowerShell profile)
Add-Content $PROFILE "`n`$env:AWS_PROFILE='${developer_name}'"
```

---

### 4. Access via AWS Console

**Method 1: Role Switching**
1. Log into AWS Console with your management account
2. Click your username (top right) → **Switch Role**
3. Enter:
   - **Account**: `${account_id}`
   - **Role**: `DeveloperRole`
   - **Display Name**: `${developer_name}`
   - **Color**: Choose a color
4. Click **Switch Role**

**Method 2: Direct URL**
```
https://signin.aws.amazon.com/switchrole?account=${account_id}&roleName=DeveloperRole&displayName=${developer_name}
```

---

### 5. Initialize Terraform in Your Account

Create a new directory for your infrastructure:

**Bash/Linux/Mac:**
```bash
mkdir -p ~/projects/${developer_name}-infrastructure
cd ~/projects/${developer_name}-infrastructure
```

**PowerShell:**
```powershell
New-Item -ItemType Directory -Path "$HOME\projects\${developer_name}-infrastructure" -Force
cd "$HOME\projects\${developer_name}-infrastructure"
```

Create your `main.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "${bucket_name}"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "bose-dev-${developer_name}-terraform-locks"
    encrypt        = true
    profile        = "${developer_name}"
  }
}

provider "aws" {
  region  = "us-west-2"
  profile = "${developer_name}"
}

# Your resources go here
```

Initialize Terraform:

**Bash/Linux/Mac:**
```bash
export AWS_PROFILE=${developer_name}
terraform init
terraform plan
```

**PowerShell:**
```powershell
$env:AWS_PROFILE="${developer_name}"
terraform init
terraform plan
```

---

## Available AWS Services

Your account has PowerUserAccess with the following restrictions:

### Allowed Services
- **Compute**: EC2, Lambda, ECS, EKS
- **Storage**: S3, EBS
- **Database**: RDS, DynamoDB
- **Networking**: VPC, ALB/NLB, CloudFront
- **Messaging**: SQS, SNS
- **Monitoring**: CloudWatch, CloudWatch Logs
- **IAM**: Limited (can create roles/policies with restrictions)

### Restricted Services
- **Billing/Cost Management**: No access
- **AWS Organizations**: No access
- **AWS Marketplace**: No access
- **Expensive EC2 Instances**: Only t3/t4g nano/micro/small/medium allowed

### Allowed Regions
- `us-east-1` (US East - N. Virginia)
- `us-east-2` (US East - Ohio)

---

## Budget Monitoring

Your account has automatic budget monitoring:

- **Budget Limit**: $${budget_limit} per month
- **80% Alert**: Email notification at $${ (budget_limit * 0.8) } spent
- **90% Forecast**: Email notification when forecasted to exceed 90%

### ⚠️ Important Budget Information

> **Warning:** If spending reaches the budget limit ($${budget_limit}), non-essential resources may be automatically terminated. You will receive notifications via email prior to any termination action, allowing you to take corrective measures or request an exception from the infrastructure team.

**Budget Best Practices:**
- Always use `t3.micro` or `t3.small` instances for development
- Stop EC2 instances when not in use
- Use S3 lifecycle policies to transition old data to cheaper storage
- Set up CloudWatch alarms for your own cost tracking
- Delete unused resources regularly

---

## Quick Reference Commands

### Check Current Costs

**Bash/Linux/Mac & PowerShell:**
```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '1 month ago' +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --profile ${developer_name}
```

### List Running EC2 Instances

**Bash/Linux/Mac & PowerShell:**
```bash
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,State:State.Name}" \
  --output table \
  --profile ${developer_name}
```

### List S3 Buckets

**Bash/Linux/Mac & PowerShell:**
```bash
aws s3 ls --profile ${developer_name}
```

### Assume Role Programmatically

**Bash/Linux/Mac:**
```bash
CREDS=$(aws sts assume-role \
  --role-arn ${role_arn} \
  --role-session-name my-session)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')
```

**PowerShell:**
```powershell
$Creds = aws sts assume-role `
  --role-arn ${role_arn} `
  --role-session-name my-session | ConvertFrom-Json

$env:AWS_ACCESS_KEY_ID = $Creds.Credentials.AccessKeyId
$env:AWS_SECRET_ACCESS_KEY = $Creds.Credentials.SecretAccessKey
$env:AWS_SESSION_TOKEN = $Creds.Credentials.SessionToken
```

---

## Troubleshooting

### "Access Denied" Errors

1. **Check your profile is set:**
   ```bash
   echo $AWS_PROFILE                    # Bash
   echo $env:AWS_PROFILE                # PowerShell
   ```

2. **Verify you can assume the role:**
   ```bash
   aws sts get-caller-identity --profile ${developer_name}
   ```

3. **Check if service is allowed:**
   - Review the "Available AWS Services" section above
   - Ensure you're operating in allowed regions

### Budget Alerts Not Received

- Check your email inbox and spam folder
- Verify email address: Check with infrastructure team
- SNS subscriptions require confirmation (check for confirmation email)

### Terraform State Lock Issues

**Bash/Linux/Mac & PowerShell:**
```bash
# Force unlock (use with caution!)
terraform force-unlock <LOCK_ID> -force
```

---

## Support

- **Documentation**: [Internal Wiki Link]
- **Questions**: infrastructure-team@boseprofessional.com
- **Issues**: Create Jira ticket in INFRA project
- **Emergency**: Contact DevOps on-call via PagerDuty

---

## Best Practices

1. **Tag all resources** with at least:
   - `Name`: Descriptive name
   - `Environment`: `development`
   - `Owner`: `${developer_name}`
   - `ManagedBy`: `terraform`

2. **Use Terraform for all infrastructure**
   - Store code in Git
   - Use remote state (already configured)
   - Review plans before applying

3. **Security**
   - Never commit AWS credentials to Git
   - Use IAM roles, not access keys
   - Enable MFA on your management account
   - Regularly rotate any credentials you create

4. **Cost Optimization**
   - Stop resources when not in use
   - Use spot instances for testing
   - Set up CloudWatch billing alarms
   - Review costs weekly

5. **Clean Up**
   - Delete unused resources immediately
   - Set TTL tags on temporary resources
   - Use lifecycle policies for S3

---

**Account Created**: $(date)
**Generated by**: Terraform Account Factory
**Version**: 1.1