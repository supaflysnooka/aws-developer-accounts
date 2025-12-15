# AWS Developer Account Factory - Getting Started Guide

## Table of Contents
1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Initial Setup](#initial-setup)
4. [Quick Start: Your First Account](#quick-start-your-first-account)
5. [Common Workflows](#common-workflows)
6. [Understanding the System](#understanding-the-system)
7. [Troubleshooting](#troubleshooting)
8. [Advanced Topics](#advanced-topics)
9. [Reference](#reference)

---

## Introduction

Welcome! This guide will walk you through everything you need to know to create and manage AWS developer accounts using our Terraform-based account factory. Whether you're creating your first account or updating an existing one, this guide has you covered.

**What This System Does:**
- Automates AWS account creation in our AWS Organization
- Sets up security guardrails (permission boundaries, SCPs)
- Configures networking and base infrastructure
- Implements cost controls and budgets
- Provides consistent, repeatable account configurations

**Time Investment:**
- Reading this guide: ~20 minutes
- Creating your first account: ~30-45 minutes (including AWS provisioning time)

---

## Prerequisites

Before you begin, ensure you have:

### Required Access
- [ ] AWS SSO access to the Bose Professional organization
- [ ] Permissions to create accounts in AWS Organizations
- [ ] Access to the `aws-developer-accounts` repository
- [ ] Terraform backend access (S3 bucket and DynamoDB table)

### Required Tools
- [ ] **Terraform** (version 1.5.0 or higher)
  ```bash
  terraform version
  ```
- [ ] **AWS CLI** (version 2.x)
  ```bash
  aws --version
  ```
- [ ] **Git**
- [ ] **PowerShell Core** (for Windows users) OR **Bash** (for Linux/Mac users)

### System Requirements
- Internet connectivity to AWS
- Sufficient disk space for Terraform state and modules (~500MB)

### Knowledge Prerequisites
- Basic understanding of AWS services (IAM, VPC, EC2)
- Familiarity with Terraform syntax
- Command line/terminal usage

---

## Initial Setup

### Step 1: Clone the Repository

```bash
git clone <repository-url>/aws-developer-accounts.git
cd aws-developer-accounts
```

### Step 2: Configure AWS Authentication

You have two authentication options:

#### Option A: AWS SSO (Recommended)
```bash
# Configure SSO profile
aws configure sso

# Login to SSO
aws sso login --profile <your-sso-profile>

# Set environment variable
export AWS_PROFILE=<your-sso-profile>  # Linux/Mac
$env:AWS_PROFILE="<your-sso-profile>"  # PowerShell
```

#### Option B: IAM User Credentials
```bash
# Set credentials
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_SESSION_TOKEN="your-session-token"  # If using temporary credentials
```

**Verify Authentication:**
```bash
aws sts get-caller-identity
```

You should see your account ID, user ID, and ARN.

### Step 3: Initialize Terraform Backend

The account factory uses a remote backend for state management.

```bash
# Navigate to the root directory
cd aws-developer-accounts

# Initialize Terraform
terraform init
```

**Expected Output:**
```
Initializing the backend...
Successfully configured the backend "s3"!
Initializing provider plugins...
Terraform has been successfully initialized!
```

**Troubleshooting Backend Issues:**
- If you see `Error loading state`: Verify S3 bucket and DynamoDB table access
- If you see `AccessDenied`: Check your IAM permissions for S3 and DynamoDB
- See [Troubleshooting](#troubleshooting) section for detailed solutions

### Step 4: Review Repository Structure

```
aws-developer-accounts/
├── README.md                          # Main documentation
├── GETTING_STARTED.md                 # This guide
├── main.tf                            # Root Terraform configuration
├── variables.tf                       # Input variables
├── outputs.tf                         # Output values
├── terraform.tfvars                   # Variable values (customize this)
├── scripts/                           # Helper automation scripts
│   ├── create-account.ps1            # PowerShell account creation wrapper
│   ├── create-account.sh             # Bash account creation wrapper
│   ├── validate-account.ps1          # Account validation script
│   ├── validate-account.sh           # Account validation script
│   └── README.md                     # Script documentation
└── modules/
    └── account-factory/              # Core account factory module
        ├── README.md                 # Module documentation
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── scripts/                  # Module-level scripts
            ├── setup-networking.sh
            ├── configure-security.sh
            └── README.md
```

---

## Quick Start: Your First Account

Let's create your first developer account. This walkthrough uses default settings for simplicity.

### Step 1: Define Your Account

Create or edit `terraform.tfvars`:

```hcl
# Basic account information
account_name = "dev-john-smith"
account_email = "john.smith+dev@boseprofessional.com"
account_owner = "John Smith"

# Organizational settings
organizational_unit = "DeveloperAccounts"

# Budget (optional but recommended)
monthly_budget_amount = 100

# Permission boundary (applies to all IAM users/roles)
permission_boundary_arn = "arn:aws:iam::123456789012:policy/DeveloperPermissionBoundary"

# Tags
tags = {
  Environment = "Development"
  Owner       = "John Smith"
  CostCenter  = "Engineering"
  ManagedBy   = "Terraform"
}
```

**Important Notes:**
- Email must be unique across ALL AWS accounts globally
- Use `+` addressing for testing: `yourname+dev1@boseprofessional.com`, `yourname+dev2@boseprofessional.com`
- Account name should follow naming convention: `dev-<firstname-lastname>`

### Step 2: Plan the Account Creation

Always review changes before applying:

```bash
terraform plan
```

**Review the output carefully:**
- Verify account email is correct
- Check budget amount
- Confirm organizational unit placement
- Review all resource configurations

**Common Issues at This Stage:**
- `Email already exists`: Solution: Change the email address
- `Invalid organizational unit`: Solution: Verify OU exists in AWS Organizations
- `Permission denied`: Solution: Check your AWS credentials

### Step 3: Create the Account

```bash
terraform apply
```

Type `yes` when prompted.

**What Happens During Creation:**
1. AWS Organizations creates the new account (~2-5 minutes)
2. Terraform assumes role into the new account
3. Base infrastructure is provisioned:
   - IAM permission boundaries
   - VPC and networking (if configured)
   - CloudWatch log groups
   - Cost allocation tags
   - Budgets and alerts
4. Security configurations are applied
5. Compliance checks are enabled

**Total Time:** 10-15 minutes

### Step 4: Verify Account Creation

```bash
# Get account details
terraform output

# Or use the validation script
cd scripts
./validate-account.sh dev-john-smith  # Linux/Mac
.\validate-account.ps1 -AccountName "dev-john-smith"  # PowerShell
```

**Successful Indicators:**
- Account appears in AWS Organizations console
- Terraform outputs show account ID and details
- Validation script shows all checks passing
- Budget appears in AWS Budgets console

### Step 5: Access Your New Account

```bash
# Option 1: AWS SSO (if configured)
aws sso login --profile dev-john-smith

# Option 2: Assume role
aws sts assume-role \
  --role-arn "arn:aws:iam::<new-account-id>:role/OrganizationAccountAccessRole" \
  --role-session-name "developer-session"

# Option 3: Console access via AWS SSO portal
# Navigate to: https://d-9a670c5fed.awsapps.com/start
```

---

## Common Workflows

### Creating Additional Accounts

**Scenario:** You need an additional account for a different project.

```bash
# Create new tfvars file for the second account
cp terraform.tfvars dev-account-2.tfvars

# Edit the new file
vi dev-account-2.tfvars
```

Update the values:
```hcl
account_name = "dev-john-smith-project2"
account_email = "john.smith+dev2@boseprofessional.com"
# ... other settings
```

**Apply with specific var file:**
```bash
terraform apply -var-file="dev-account-2.tfvars"
```

### Updating an Existing Account

**Scenario:** You need to increase the budget on an existing account.

1. **Edit terraform.tfvars:**
   ```hcl
   monthly_budget_amount = 200  # Changed from 100
   ```

2. **Review changes:**
   ```bash
   terraform plan
   ```

3. **Apply update:**
   ```bash
   terraform apply
   ```

**Safe Updates:**
- Budget amounts
- Tags
- CloudWatch settings
- IAM policies (with caution)

**Potentially Dangerous Updates (these require careful review):**
- Account email (may require account closure and recreation)
- Organizational unit (may affect SCPs)
- Permission boundaries (can break existing resources)

### Updating Permission Boundaries for Existing Accounts

**Scenario:** You've added new AWS services to the permission boundary and need to update existing developer accounts.

**Using the update script (Recommended):**

**PowerShell:**
```powershell
# Find account ID
$AccountId = aws organizations list-accounts --query "Accounts[?Name=='bose-dev-frank-caputo'].Id" --output text

# Update the account
.\scripts\update-existing-acct.ps1 -AccountId $AccountId -DeveloperName "frank-caputo"
```

**Bash:**
```bash
# Find account ID
ACCOUNT_ID=$(aws organizations list-accounts --query "Accounts[?Name=='bose-dev-frank-caputo'].Id" --output text)

# Update the account
./scripts/update-existing-acct.sh $ACCOUNT_ID frank-caputo
```

**What gets updated:**
1. Permission boundary policy (creates new version with latest services)
2. DeveloperRole gets boundary attached if missing
3. Old policy versions automatically cleaned up (AWS limit: 5 versions)

**Bulk update multiple accounts:**
```bash
# Create a list of accounts to update
accounts=(
    "frank-caputo:123456789012"
    "jane-doe:234567890123"
    "john-smith:345678901234"
)

# Update each account
for account in "${accounts[@]}"; do
    IFS=':' read -r name id <<< "$account"
    echo "Updating $name..."
    ./scripts/update-existing-acct.sh $id $name
    sleep 5  #5s Pause
done
```

### Adding or Modifying Budgets

**Scenario:** Add multiple budget thresholds with different alert levels.

Edit your configuration:

```hcl
monthly_budget_amount = 150

budget_alerts = [
  {
    threshold      = 50
    threshold_type = "PERCENTAGE"
    notification_type = "ACTUAL"
    subscriber_email_addresses = ["team-lead@boseprofessional.com"]
  },
  {
    threshold      = 80
    threshold_type = "PERCENTAGE"
    notification_type = "ACTUAL"
    subscriber_email_addresses = ["team-lead@boseprofessional.com", "manager@boseprofessional.com"]
  },
  {
    threshold      = 100
    threshold_type = "PERCENTAGE"
    notification_type = "FORECASTED"
    subscriber_email_addresses = ["team-lead@boseprofessional.com", "manager@boseprofessional.com", "finance@boseprofessional.com"]
  }
]
```

Apply the changes:
```bash
terraform apply
```

### Modifying Permission Boundaries

**Scenario:** Update the permission boundary policy for an account

**WARNING:** This is a very sensitive operation that can break existing IAM resources

1. **Update the permission boundary policy in IAM:**
   ```bash
   # Review current policy
   aws iam get-policy --policy-arn "arn:aws:iam::123456789012:policy/DeveloperPermissionBoundary"
   
   # Update policy (do this in the management account)
   aws iam create-policy-version \
     --policy-arn "arn:aws:iam::123456789012:policy/DeveloperPermissionBoundary" \
     --policy-document file://new-policy.json \
     --set-as-default
   ```

2. **Update terraform.tfvars if changing the ARN:**
   ```hcl
   permission_boundary_arn = "arn:aws:iam::123456789012:policy/DeveloperPermissionBoundaryV2"
   ```

3. **Plan and apply carefully:**
   ```bash
   terraform plan  # Review all IAM changes carefully
   terraform apply
   ```

**Testing Permission Boundaries:**
Always test permission boundary changes in a non-production account first.

### Decommissioning an Account

**Scenario:** Developer no longer needs the account

**NOTE:  This is a multi-step process that cannot be easily reversed**

1. **Document current state:**
   ```bash
   terraform show > account-state-backup.txt
   aws resourcegroupstaggingapi get-resources --region us-east-1 > resources-backup.json
   ```

2. **Remove from Terraform management:**
   ```bash
   terraform destroy
   ```

3. **Close the account in AWS Organizations:**
   - Must be done via AWS Console or CLI
   - Account enters 90-day suspension period
   - Can be recovered during suspension period

4. **Update documentation:**
   - Remove tfvars file
   - Update any references
   - Notify stakeholders

### Using Helper Scripts

The `aws-developer-accounts/scripts/account-management` directory contains automation helpers to simplify common tasks.

#### Account Creation Script (Recommended for New Users)

**PowerShell:**
```powershell
cd aws-developer-accounts/scripts/account-management
.\create-account.ps1 `
  -AccountName "dev-jane-doe" `
  -AccountEmail "jane.doe+dev@boseprofessional.com" `
  -AccountOwner "Jane Doe" `
  -MonthlyBudget 100 `
  -OU "DeveloperAccounts"
```

**Bash:**
```bash
cd aws-developer-accounts/scripts/account-management
./create-account.sh \
  --account-name "dev-jane-doe" \
  --account-email "jane.doe+dev@boseprofessional.com" \
  --account-owner "Jane Doe" \
  --monthly-budget 100 \
  --ou "DeveloperAccounts"
```

**What the script does:**
1. Validates inputs
2. Checks for existing accounts with same email
3. Generates terraform.tfvars
4. Runs terraform plan
5. Prompts for confirmation
6. Runs terraform apply
7. Validates the new account
8. Outputs access information

#### Account Validation Script

Run after any account changes:

**PowerShell:**
```powershell
.\validate-account.ps1 -AccountName "dev-jane-doe" -Verbose
```

**Bash:**
```bash
./validate-account.sh dev-jane-doe --verbose
```

**Checks performed:**
- Account exists in AWS Organizations
- IAM permission boundaries are applied
- Budget is configured correctly
- Required tags are present
- Security configurations are in place
- Networking is properly configured
- Compliance checks are passing

---

## Understanding the System

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Organizations                        │
│                   (Management Account)                      │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ Creates & Manages
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│              Organizational Unit (OU)                       │
│              "DeveloperAccounts"                            │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │Dev Account 1 │  │Dev Account 2 │  │Dev Account N │       │
│  │              │  │              │  │              │       │
│  │ • VPC        │  │ • VPC        │  │ • VPC        │       │
│  │ • Budgets    │  │ • Budgets    │  │ • Budgets    │       │
│  │ • IAM        │  │ • IAM        │  │ • IAM        │       │
│  │ • Logging    │  │ • Logging    │  │ • Logging    │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### How Account Creation Works

1. **Terraform Invocation:**
   - You run `terraform apply`
   - Terraform reads your `terraform.tfvars` configuration (or what is in the variables.tf file if you are using the default values)

2. **Organization Account Creation:**
   - Module calls `aws_organizations_account` resource
   - AWS creates the account (async, takes 2-5 minutes)
   - Returns account ID

3. **Role Assumption:**
   - Terraform assumes `OrganizationAccountAccessRole` in new account
   - This role has full admin permissions in the member account

4. **Infrastructure Provisioning:**
   - IAM permission boundaries created
   - VPC and networking configured (if enabled)
   - Budgets and cost controls set up
   - CloudWatch logging configured
   - Security baseline applied

5. **Tagging and Metadata:**
   - Cost allocation tags applied
   - Resource tags for compliance
   - Account metadata stored in Terraform state

6. **Validation:**
   - Built-in checks verify configuration
   - Outputs provide access information

### Module Structure

#### Root Module (`aws-developer-accounts/`)
- **Purpose:** Entry point for account creation
- **Key Files:**
  - `main.tf`: Calls the account-factory module
  - `variables.tf`: Defines inputs
  - `terraform.tfvars`: Your configuration values
  - `outputs.tf`: Account details after creation

#### Account Factory Module (`modules/account-factory/`)
- **Purpose:** Core logic for account provisioning
- **Responsibilities:**
  - Account creation in AWS Organizations
  - IAM configuration
  - Network setup
  - Budget creation
  - Security baseline

#### Scripts (`scripts/` and `modules/account-factory/scripts/`)
- **Purpose:** Automation helpers and utilities
- **Types:**
  - Wrapper scripts (simplify Terraform usage)
  - Validation scripts (verify configurations)
  - Setup scripts (post-creation configuration)
  - Utility scripts (bulk operations, reporting)

### Security Model

#### Permission Boundaries
Every IAM user and role in developer accounts must have a permission boundary attached. This acts as a "maximum permissions" guardrail.

**Example Permission Boundary:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "ec2:*",
        "lambda:*",
        "dynamodb:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": ["us-east-1", "us-west-2"]
        }
      }
    },
    {
      "Effect": "Deny",
      "Action": [
        "iam:DeleteUserPermissionsBoundary",
        "iam:DeleteRolePermissionsBoundary",
        "organizations:*"
      ],
      "Resource": "*"
    }
  ]
}
```

**Key Concepts:**
- Developers cannot remove or bypass the boundary
- Boundaries limit maximum permissions, not grant them
- Separate IAM policies grant actual permissions
- Boundaries prevent privilege escalation

#### Service Control Policies (SCPs)
Applied at the OU level to restrict account capabilities:

**Common SCP Restrictions:**
- Prevent leaving the organization
- Block root user API access
- Enforce encryption requirements
- Restrict service usage by region
- Prevent security tool disablement

#### Assume Role Pattern
Access to developer accounts uses cross-account role assumption:

```bash
# From management account
aws sts assume-role \
  --role-arn "arn:aws:iam::123456789012:role/OrganizationAccountAccessRole" \
  --role-session-name "my-session"
```

### Cost Management

#### Budget Alerts
Budgets trigger notifications at defined thresholds:

- **50% threshold:** Warning to account owner
- **80% threshold:** Alert to account owner and manager
- **100% threshold:** Critical alert to finance team
- **Forecasted overage:** Alert before reaching limit

#### Cost Allocation Tags
Automatically applied to track spending:

```hcl
tags = {
  Environment = "Development"
  Owner       = "John Smith"
  CostCenter  = "Engineering"
  ManagedBy   = "Terraform"
  Project     = "CloudMigration"
}
```

#### Resource Tagging Strategy
All resources should inherit account-level tags plus:
- Application-specific tags
- Data classification tags
- Compliance tags

### Networking Architecture

#### Default VPC Configuration
Each account gets a VPC with:

```
VPC CIDR: 10.x.0.0/16 (x = unique per account)
├── Public Subnets (3 AZs)
│   ├── 10.x.1.0/24 (us-east-1a)
│   ├── 10.x.2.0/24 (us-east-1b)
│   └── 10.x.3.0/24 (us-east-1c)
├── Private Subnets (3 AZs)
│   ├── 10.x.11.0/24 (us-east-1a)
│   ├── 10.x.12.0/24 (us-east-1b)
│   └── 10.x.13.0/24 (us-east-1c)
├── Internet Gateway
├── NAT Gateways (1 per AZ)
└── Route Tables
```

#### VPC Features
- **Flow Logs:** Enabled by default, sent to CloudWatch
- **DNS Resolution:** Enabled
- **DNS Hostnames:** Enabled
- **DHCP Options:** Default
- **Network ACLs:** Default allow all (use security groups)

---

## Troubleshooting

### Authentication Issues

#### Problem: "Error: error configuring Terraform AWS Provider: no valid credential sources"

**Solution:**
```bash
# Verify AWS credentials are set
aws sts get-caller-identity

# If using SSO, re-login
aws sso login --profile <your-profile>

# Export profile
export AWS_PROFILE=<your-profile>
```

#### Problem: "AccessDenied" when running Terraform

**Checklist:**
- [ ] Verify you have permissions in management account
- [ ] Check if MFA is required for your operations
- [ ] Ensure SSO session hasn't expired
- [ ] Verify you're using the correct AWS profile

**Verify Permissions:**
```bash
# Check your current identity
aws sts get-caller-identity

# Test Organizations access
aws organizations describe-organization

# Test S3 backend access
aws s3 ls s3://<terraform-backend-bucket>
```

### Terraform Backend Issues

#### Problem: "Error loading state: AccessDenied"

**Causes:**
- S3 bucket permissions missing
- DynamoDB table permissions missing
- Bucket encryption incompatibility
- Incorrect bucket name/region

**Solution:**
```bash
# Verify S3 access
aws s3 ls s3://<backend-bucket-name>/

# Verify DynamoDB access
aws dynamodb describe-table --table-name <state-lock-table>

# Re-initialize backend
terraform init -reconfigure
```

#### Problem: "Error acquiring the state lock"

**Cause:** Another Terraform process is running or crashed without releasing the lock.

**Solution:**
```bash
# List locks
aws dynamodb scan --table-name <state-lock-table>

# If you're CERTAIN no other process is running:
terraform force-unlock <lock-id>
```

**WARNING:** Only force-unlock if you're absolutely sure no other Terraform process is running.

### Account Creation Failures

#### Problem: "Email address already exists"

**Solution:**
```bash
# Use + addressing for unique emails
# Instead of: john.smith@boseprofessional.com
# Use: john.smith+dev1@boseprofessional.com, john.smith+dev2@boseprofessional.com

# Verify email uniqueness
aws organizations list-accounts | grep "john.smith+dev1"
```

#### Problem: Account created but Terraform failed during provisioning

**Symptoms:**
- Account exists in Organizations
- Terraform state is incomplete
- Resources partially created

**Solution:**
```bash
# Import the account into Terraform state
terraform import aws_organizations_account.account <account-id>

# Run apply again to complete provisioning
terraform apply
```

#### Problem: "Error assuming OrganizationAccountAccessRole"

**Cause:** Role doesn't exist or trust policy is incorrect.

**Solution:**
```bash
# Verify role exists in member account
aws iam get-role \
  --role-name OrganizationAccountAccessRole \
  --profile <member-account-profile>

# If role is missing, it must be created manually
# (This usually happens with imported accounts)
```

### Updating Existing Accounts

#### Problem: "User is not authorized to perform: sts:AssumeRole on resource: arn:aws:iam:::role/OrganizationAccountAccessRole"

**Symptom:**
When running update scripts, you see an error with **three colons** in the ARN (missing account ID):
```
An error occurred (AccessDenied) when calling the AssumeRole operation: 
User: arn:aws:sts::515331791591:assumed-role/AWSReservedSSO_AWSAdministratorAccess_ca035c15df0ea61b/frank.caputo@boseprofessional.com 
is not authorized to perform: sts:AssumeRole on resource: arn:aws:iam:::role/OrganizationAccountAccessRole
```

**Cause:**
The script is not receiving the account ID parameter, so it constructs a malformed ARN.

**Solution:**

**For PowerShell:**
```powershell
# Step 1: Find the target account ID
$AccountId = aws organizations list-accounts --query "Accounts[?Name=='bose-dev-frank-caputo'].Id" --output text

# Step 2: Verify you got a valid 12-digit account ID
Write-Host "Account ID: $AccountId"

# Step 3: Run the update script with explicit parameters
.\scripts\update-existing-acct.ps1 -AccountId $AccountId -DeveloperName "frank-caputo"
```

**For Bash:**
```bash
# Step 1: Find the target account ID
ACCOUNT_ID=$(aws organizations list-accounts --query "Accounts[?Name=='bose-dev-frank-caputo'].Id" --output text)

# Step 2: Verify you got a valid 12-digit account ID
echo "Account ID: $ACCOUNT_ID"

# Step 3: Run the update script with explicit parameters
./scripts/update-existing-acct.sh $ACCOUNT_ID frank-caputo
```

**What the update script does:**
1. Validates the account ID format (12 digits)
2. Assumes role into the target account
3. Updates the permission boundary policy with latest services
4. Attaches the boundary to DeveloperRole if missing
5. Manages policy version limits automatically
6. Provides detailed status output

**Common mistakes:**
- Forgetting to pass the account ID as a parameter
- Passing the account name instead of the account ID
- Using an empty or malformed account ID variable

### Permission Boundary Issues

#### Problem: "Cannot create IAM resource: permission boundary required"

**Solution:**
Ensure your IAM policies include permission boundary:

```hcl
resource "aws_iam_role" "example" {
  name                 = "example-role"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  permissions_boundary = var.permission_boundary_arn  # Must include this
}
```

#### Problem: "Cannot perform action: permission boundary denies"

**Solution:**
The permission boundary is working as intended. Options:
1. Modify the permission boundary policy (requires management account access)
2. Request specific permissions be added to boundary
3. Use a different approach that works within boundary constraints

### Budget Issues

#### Problem: Budget notifications not received

**Checklist:**
- [ ] Email addresses are verified in SNS
- [ ] Budget thresholds are correctly configured
- [ ] SNS topic has correct permissions
- [ ] Email didn't go to spam folder

**Solution:**
```bash
# Verify budget configuration
aws budgets describe-budget \
  --account-id <account-id> \
  --budget-name <budget-name>

# Check SNS topic
aws sns list-subscriptions-by-topic \
  --topic-arn <budget-sns-topic-arn>

# Resend confirmation email
aws sns subscribe \
  --topic-arn <topic-arn> \
  --protocol email \
  --notification-endpoint your-email@boseprofessional.com
```

### Validation Script Failures

#### Problem: Validation script reports failures

**Steps:**
1. Run validation with verbose flag:
   ```bash
   ./validate-account.sh dev-account-name --verbose
   ```

2. Review specific failure messages

3. Common failures and fixes:
   - **Missing tags:** Update terraform.tfvars and apply
   - **Permission boundary not applied:** Check IAM resources
   - **Budget misconfigured:** Review budget configuration
   - **VPC issues:** Check VPC module configuration

### Network Connectivity Issues

#### Problem: Cannot reach internet from private subnet

**Checklist:**
- [ ] NAT Gateway exists and is running
- [ ] Route table has default route to NAT Gateway
- [ ] Security groups allow outbound traffic
- [ ] Network ACLs allow traffic
- [ ] EC2 instance has correct route table association

**Solution:**
```bash
# Check NAT Gateway
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=<vpc-id>"

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<vpc-id>"

# Verify instance route table
aws ec2 describe-instances --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].SubnetId'
```

### Terraform State Issues

#### Problem: "Resource already exists but not in state"

**Solution:**
```bash
# Import existing resource
terraform import <resource_type>.<resource_name> <resource_id>

# Example: Import an existing VPC
terraform import aws_vpc.main vpc-12345678
```

#### Problem: State drift detected

**Solution:**
```bash
# View current state
terraform show

# Refresh state from AWS
terraform refresh

# If drift is intentional, update code to match
# If drift is unwanted, apply to fix
terraform apply
```

### Getting Help

If you're still stuck:

1. **Check the detailed module documentation:**
   - `/modules/account-factory/README.md`
   - `/scripts/README.md`

2. **Review Terraform logs:**
   ```bash
   export TF_LOG=DEBUG
   terraform apply 2>&1 | tee terraform-debug.log
   ```

3. **Search for similar issues:**
   - Check repository issues
   - Search AWS documentation
   - Review Terraform registry

4. **Contact the infrastructure team:**
   - Include: account name, error messages, terraform output
   - Attach: debug logs, tfvars (remove sensitive data)
   - Describe: what you were trying to do, what happened instead

---

## Advanced Topics

### Managing Multiple Accounts with Workspaces

Terraform workspaces allow managing multiple accounts from one configuration:

```bash
# Create workspace for account
terraform workspace new dev-john-smith

# Switch to workspace
terraform workspace select dev-john-smith

# Apply configuration
terraform apply -var-file="dev-john-smith.tfvars"

# List workspaces
terraform workspace list
```

**Pros:**
- Single repository for all accounts
- Shared modules and configuration
- Easy to see all accounts

**Cons:**
- Shared state file (more complex)
- Easy to accidentally modify wrong account
- Requires discipline with workspace selection

### Custom Module Development

Want to extend the account factory?

**Example: Adding custom CloudWatch dashboards**

1. **Create module:**
   ```bash
   mkdir -p modules/cloudwatch-dashboard
   cd modules/cloudwatch-dashboard
   ```

2. **Define module:**
   ```hcl
   # main.tf
   resource "aws_cloudwatch_dashboard" "main" {
     dashboard_name = var.dashboard_name
     dashboard_body = jsonencode({
       widgets = var.widgets
     })
   }
   ```

3. **Integrate into account factory:**
   ```hcl
   # In modules/account-factory/main.tf
   module "dashboard" {
     source = "../cloudwatch-dashboard"
     
     dashboard_name = "AccountOverview"
     widgets        = local.dashboard_widgets
     
     depends_on = [aws_organizations_account.this]
   }
   ```

### Automation and CI/CD

**GitHub Actions Example:**

```yaml
name: Create Developer Account

on:
  workflow_dispatch:
    inputs:
      account_name:
        description: 'Account Name'
        required: true
      account_email:
        description: 'Account Email'
        required: true
      monthly_budget:
        description: 'Monthly Budget'
        required: true
        default: '100'

jobs:
  create_account:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.0
      
      - name: Create tfvars
        run: |
          cat << EOF > terraform.tfvars
          account_name = "${{ github.event.inputs.account_name }}"
          account_email = "${{ github.event.inputs.account_email }}"
          monthly_budget_amount = ${{ github.event.inputs.monthly_budget }}
          EOF
      
      - name: Terraform Init
        run: terraform init
      
      - name: Terraform Plan
        run: terraform plan
      
      - name: Terraform Apply
        run: terraform apply -auto-approve
      
      - name: Validate Account
        run: ./scripts/validate-account.sh ${{ github.event.inputs.account_name }}
```

### Bulk Operations

**Scenario:** Create 10 developer accounts at once

**Using script with loop:**

```bash
# accounts.txt format: name,email,owner,budget
# dev-john-smith,john.smith+dev@boseprofessional.com,John Smith,100
# dev-jane-doe,jane.doe+dev@boseprofessional.com,Jane Doe,150

while IFS=',' read -r name email owner budget; do
  echo "Creating account: $name"
  ./scripts/create-account.sh \
    --account-name "$name" \
    --account-email "$email" \
    --account-owner "$owner" \
    --monthly-budget "$budget" \
    --ou "DeveloperAccounts"
  
  sleep 60  # Wait between account creations
done < accounts.txt
```

**Using Terraform for_each:**

```hcl
# terraform.tfvars
accounts = {
  "dev-john-smith" = {
    email  = "john.smith+dev@boseprofessional.com"
    owner  = "John Smith"
    budget = 100
  }
  "dev-jane-doe" = {
    email  = "jane.doe+dev@boseprofessional.com"
    owner  = "Jane Doe"
    budget = 150
  }
}

# main.tf
module "accounts" {
  source = "./modules/account-factory"
  
  for_each = var.accounts
  
  account_name          = each.key
  account_email         = each.value.email
  account_owner         = each.value.owner
  monthly_budget_amount = each.value.budget
}
```

### Cross-Account Access Patterns

**Scenario:** Account A needs access to resources in Account B

**Option 1: IAM Role Trust**

In Account B:
```hcl
resource "aws_iam_role" "cross_account" {
  name = "CrossAccountAccess"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::ACCOUNT-A-ID:root"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
```

In Account A:
```bash
aws sts assume-role \
  --role-arn "arn:aws:iam::ACCOUNT-B-ID:role/CrossAccountAccess" \
  --role-session-name "cross-account-session"
```

**Option 2: Resource-Based Policies**

```hcl
# S3 bucket in Account B allows access from Account A
resource "aws_s3_bucket_policy" "allow_cross_account" {
  bucket = aws_s3_bucket.shared.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::ACCOUNT-A-ID:root"
      }
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.shared.arn,
        "${aws_s3_bucket.shared.arn}/*"
      ]
    }]
  })
}
```

### Disaster Recovery

**Scenario:** Terraform state file is corrupted or lost

**Prevention:**
1. Enable S3 versioning on state bucket
2. Enable S3 replication to backup region
3. Regular state backups
4. Document all manual changes

**Recovery Steps:**

```bash
# 1. Restore state from S3 version
aws s3api list-object-versions \
  --bucket <state-bucket> \
  --prefix <state-key>

aws s3api get-object \
  --bucket <state-bucket> \
  --key <state-key> \
  --version-id <version-id> \
  terraform.tfstate.backup

# 2. Restore to current state file location
cp terraform.tfstate.backup terraform.tfstate

# 3. Verify state
terraform show

# 4. Refresh from AWS
terraform refresh

# 5. Fix any drift
terraform plan
terraform apply
```

### Compliance and Auditing

**Generating Compliance Reports:**

```bash
# List all accounts with their configurations
terraform state list | grep aws_organizations_account

# Export account details
terraform show -json > accounts-config.json

# Generate compliance report
cat accounts-config.json | jq '.values.root_module.child_modules[] | 
  select(.address | contains("account")) | 
  {
    account: .resources[0].values.name,
    budget: .resources[1].values.limit_amount,
    permission_boundary: .resources[2].values.permissions_boundary
  }'
```

**Automated Compliance Scanning:**

```bash
# Run validation across all accounts
for account in $(terraform state list | grep aws_organizations_account); do
  account_name=$(terraform state show $account | grep "name " | awk '{print $3}')
  echo "Validating: $account_name"
  ./scripts/validate-account.sh $account_name
done
```

---

## Reference

### Terraform Variables Reference

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `account_name` | string | Yes | - | Name of the AWS account |
| `account_email` | string | Yes | - | Email address for the account (must be unique) |
| `account_owner` | string | Yes | - | Name of the account owner |
| `organizational_unit` | string | No | "DeveloperAccounts" | OU to place account in |
| `monthly_budget_amount` | number | No | 100 | Monthly budget in USD |
| `permission_boundary_arn` | string | No | null | ARN of IAM permission boundary |
| `tags` | map(string) | No | {} | Tags to apply to the account |
| `enable_vpc` | bool | No | true | Create default VPC |
| `vpc_cidr` | string | No | "10.0.0.0/16" | VPC CIDR block |
| `availability_zones` | list(string) | No | ["us-east-1a", "us-east-1b", "us-east-1c"] | AZs for subnets |
| `enable_flow_logs` | bool | No | true | Enable VPC Flow Logs |
| `enable_nat_gateway` | bool | No | true | Create NAT Gateways |
| `budget_alerts` | list(object) | No | See example | Budget alert thresholds |

### Outputs Reference

| Output | Description |
|--------|-------------|
| `account_id` | AWS account ID |
| `account_arn` | ARN of the account |
| `account_name` | Name of the account |
| `account_email` | Email address of the account |
| `organizational_unit_id` | ID of the OU containing the account |
| `vpc_id` | VPC ID (if created) |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `budget_name` | Name of the budget |
| `permission_boundary_arn` | ARN of the permission boundary |

### Script Reference

#### create-account.ps1 / create-account.sh

**Purpose:** Wrapper script to simplify account creation

**Parameters:**
- `--account-name`: Name of the account (required)
- `--account-email`: Email address (required)
- `--account-owner`: Owner name (required)
- `--monthly-budget`: Budget amount in USD (default: 100)
- `--ou`: Organizational unit (default: DeveloperAccounts)
- `--auto-approve`: Skip confirmation prompts
- `--verbose`: Enable detailed output

**Example:**
```bash
./create-account.sh \
  --account-name "dev-john-smith" \
  --account-email "john.smith+dev@boseprofessional.com" \
  --account-owner "John Smith" \
  --monthly-budget 150 \
  --verbose
```

#### validate-account.ps1 / validate-account.sh

**Purpose:** Validate account configuration and compliance

**Parameters:**
- `ACCOUNT_NAME`: Name of the account to validate (required)
- `--verbose`: Show detailed check results
- `--json`: Output results in JSON format

**Checks Performed:**
- Account exists in AWS Organizations
- IAM permission boundaries applied
- Budget configured correctly
- Required tags present
- Security configurations
- Network configuration
- Compliance requirements

**Exit Codes:**
- 0: All checks passed
- 1: One or more checks failed
- 2: Script error

**Example:**
```bash
./validate-account.sh dev-john-smith --verbose
```

#### update-existing-acct.ps1 / update-existing-acct.sh

**Purpose:** Update existing developer accounts with latest permission boundary policy

**Parameters:**
- `AccountId` / `<account-id>`: AWS account ID (12 digits, required)
- `DeveloperName` / `<developer-name>`: Developer's name (required)

**Operations Performed:**
1. Validates account ID format
2. Assumes OrganizationAccountAccessRole in target account
3. Updates or creates permission boundary policy with latest services
4. Attaches boundary to DeveloperRole if missing
5. Automatically manages policy version limits (max 5)
6. Provides detailed success/failure feedback

**Exit Codes:**
- 0: Update completed successfully
- 1: Error during update (see output for details)

**Example (PowerShell):**
```powershell
# Find account ID first
$AccountId = aws organizations list-accounts --query "Accounts[?Name=='bose-dev-frank-caputo'].Id" --output text

# Run update
.\update-existing-acct.ps1 -AccountId $AccountId -DeveloperName "frank-caputo"

# Or with help
.\update-existing-acct.ps1 -Help
```

**Example (Bash):**
```bash
# Find account ID first
ACCOUNT_ID=$(aws organizations list-accounts --query "Accounts[?Name=='bose-dev-frank-caputo'].Id" --output text)

# Run update
./update-existing-acct.sh $ACCOUNT_ID frank-caputo

# Or with help
./update-existing-acct.sh --help
```

**Features:**
- Color-coded output for easy reading
- Comprehensive error messages
- Automatic policy version management
- Validates account ID format
- Checks AWS CLI and credential configuration
- Safe handling of existing policies and roles
- Detailed summary of changes made

### Common Error Messages

| Error | Meaning | Solution |
|-------|---------|----------|
| `DuplicateAccountException` | Email address already used | Use different email |
| `ConcurrentModificationException` | Another process is modifying the organization | Wait and retry |
| `AccessDeniedException` | Insufficient permissions | Check IAM permissions |
| `LimitExceededException` | Hit AWS account limit | Request limit increase |
| `InvalidInputException` | Invalid parameter value | Check input format |
| `AccountNotRegisteredException` | Account doesn't exist | Verify account ID |
| `TooManyRequestsException` | Rate limited | Implement backoff/retry |

### AWS Service Limits

| Resource | Default Limit | Notes |
|----------|---------------|-------|
| Accounts per organization | 10 | Increasable to 1,000+ |
| OUs per organization | 1,000 | Hard limit |
| Policies per entity | 5 | Hard limit |
| VPCs per region | 5 | Increasable |
| NAT Gateways per AZ | 5 | Increasable |
| Budget alerts per budget | 10 | Hard limit |

### Helpful AWS CLI Commands

```bash
# List all accounts in organization
aws organizations list-accounts

# Get account details
aws organizations describe-account --account-id <account-id>

# List OUs
aws organizations list-organizational-units-for-parent --parent-id <root-or-ou-id>

# Describe organization
aws organizations describe-organization

# List policies attached to account
aws organizations list-policies-for-target --target-id <account-id> --filter SERVICE_CONTROL_POLICY

# Get current costs for account
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --filter file://filter.json

# List budgets
aws budgets describe-budgets --account-id <account-id>

# Assume role into member account
aws sts assume-role \
  --role-arn "arn:aws:iam::<account-id>:role/OrganizationAccountAccessRole" \
  --role-session-name "admin-session"
```

### Additional Resources

**Internal Documentation:**
- Main README: `/README.md`
- Module README: `/modules/account-factory/README.md`
- Scripts README: `/scripts/README.md`
- Module Scripts README: `/modules/account-factory/scripts/README.md`

**AWS Documentation:**
- [AWS Organizations](https://docs.aws.amazon.com/organizations/)
- [IAM Permission Boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html)
- [AWS Budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
- [Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)

**Terraform Documentation:**
- [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform State](https://www.terraform.io/language/state)
- [Terraform Modules](https://www.terraform.io/language/modules)

**Best Practices:**
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Security Best Practices](https://docs.aws.amazon.com/security/)

---

## Quick Reference Card

**Create New Account:**
```bash
cd aws-developer-accounts
vim terraform.tfvars  # Edit configuration
terraform plan        # Review changes
terraform apply       # Create account
```

**Update Existing Account:**
```bash
vim terraform.tfvars  # Update configuration
terraform plan        # Review changes
terraform apply       # Apply updates
```

**Validate Account:**
```bash
cd scripts
./validate-account.sh <account-name>
```

**Access Account:**
```bash
aws sso login --profile <account-name>
export AWS_PROFILE=<account-name>
```

**Common Issues:**
- Email exists → Use + addressing
- Auth failed → `aws sso login`
- State locked → `terraform force-unlock`
- Resources exist → `terraform import`

**Get Help:**
- Check `/modules/account-factory/README.md`
- Check `/scripts/README.md`
- Review error logs with `TF_LOG=DEBUG`
- Contact infrastructure team

---

## Document Version

**Version:** 1.0
**Last Updated:** December 2025
**Maintainer:** Bose Professional Infrastructure Team
**Feedback:** Submit issues or suggestions to the repository

---

**You're all set!** If you have questions or run into issues not covered here, don't hesitate to reach out to Anushree, Rob or Frank.
