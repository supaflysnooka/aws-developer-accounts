# Account Factory Module

The Account Factory module automates the creation and configuration of AWS developer accounts within an AWS Organization, including budget controls, IAM configuration, and base infrastructure setup.

**Cross-Platform Support**: This module automatically detects your operating system and uses the appropriate shell interpreter (PowerShell for Windows, Bash for Unix/Linux/Mac).

## Overview

This module creates:
- AWS Organizations member account
- S3 bucket for Terraform state (with versioning and encryption)
- DynamoDB table for state locking
- IAM permission boundary policy
- IAM DeveloperRole with PowerUserAccess
- Monthly budget with email alerts
- Generated onboarding documentation
- Backend configuration file

## Prerequisites

### AWS Requirements

1. **AWS Organizations enabled** in the management account
2. **IAM Permissions** for the user/role executing Terraform:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "organizations:CreateAccount",
           "organizations:DescribeAccount",
           "organizations:ListAccounts",
           "organizations:CloseAccount",
           "iam:*",
           "sts:AssumeRole",
           "s3:*",
           "dynamodb:*",
           "budgets:*"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

### Local Requirements

#### For All Platforms
- **Terraform** >= 1.5.0
- **AWS CLI** >= 2.x
- **jq** (JSON processor for parsing AWS CLI output)

#### For Windows Users
- **PowerShell** 5.1 or later (included with Windows 10/11)
- **AWS CLI v2** for Windows
- **jq** for Windows

**Install jq on Windows:**
```powershell
# Using Chocolatey
choco install jq

# Using Scoop
scoop install jq

# Or download from https://stedolan.github.io/jq/download/
# Add jq.exe to your PATH
```

**Verify PowerShell version:**
```powershell
$PSVersionTable.PSVersion
# Should be 5.1 or higher
```

#### For Unix/Linux/Mac Users
- **bash** shell
- **jq**

**Install jq:**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq

# RHEL/CentOS/Fedora
sudo yum install jq
```

## How It Works

The module automatically detects your operating system and executes platform-specific scripts:

### Phase 1: Account Creation (Native Terraform)
```
1. Detects operating system (Windows vs Unix)
2. Creates AWS Organizations account
3. Waits 60 seconds for account provisioning
```

### Phase 2: Cross-Account Configuration (Platform-Specific Scripts)
```
Windows (PowerShell):
4. Executes configure-account.ps1
5. Executes create-permission-boundary.ps1
6. Executes create-developer-role.ps1
7. Executes create-budget.ps1

Unix/Linux/Mac (Bash):
4. Executes configure-account.sh
5. Executes create-permission-boundary.sh
6. Executes create-developer-role.sh
7. Executes create-budget.sh
```

### Phase 3: Documentation Generation
```
9. Generates backend.tf configuration
10. Generates onboarding.md documentation
```

## Platform Detection

The module uses Terraform's built-in path functions to detect the operating system:

```hcl
locals {
  is_windows = substr(pathexpand("~"), 0, 1) == "/" ? false : true
  is_unix    = !local.is_windows
  
  shell_interpreter = local.is_windows ? ["PowerShell", "-Command"] : ["/bin/bash", "-c"]
}
```

**How it works:**
- On Windows: `pathexpand("~")` returns `C:\Users\username`
- On Unix: `pathexpand("~")` returns `/home/username` or `/Users/username`
- The first character determines the platform

## Usage

### Basic Example (Works on All Platforms)

```hcl
module "developer_account" {
  source = "../../modules/account-factory"
  
  developer_name        = "john-smith"
  developer_email       = "john.smith@boseprofessional.com"
  budget_limit          = 100
  management_account_id = "123456789012"
}
```

### Running on Windows

```powershell
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -out=tfplan

# Apply the configuration
terraform apply tfplan

# The module will automatically:
# 1. Detect you're on Windows
# 2. Use PowerShell scripts
# 3. Execute AWS CLI commands via PowerShell
```

### Running on Unix/Linux/Mac

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -out=tfplan

# Apply the configuration
terraform apply tfplan

# The module will automatically:
# 1. Detect you're on Unix/Linux/Mac
# 2. Use Bash scripts
# 3. Execute AWS CLI commands via Bash
```

## Troubleshooting

### Windows-Specific Issues

#### Error: PowerShell Execution Policy

**Problem:** PowerShell scripts are blocked by execution policy.

**Solution:**
```powershell
# Check current policy
Get-ExecutionPolicy

# Set policy to allow scripts (run as Administrator)
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or bypass for this session only
Set-ExecutionPolicy Bypass -Scope Process
```

#### Error: jq: command not found (Windows)

**Problem:** jq is not installed or not in PATH.

**Solution:**
```powershell
# Option 1: Install via Chocolatey
choco install jq

# Option 2: Download manually
# 1. Download jq-win64.exe from https://github.com/stedolan/jq/releases
# 2. Rename to jq.exe
# 3. Place in C:\Windows\System32 or add to PATH

# Verify installation
jq --version
```

#### Error: AWS CLI not found

**Problem:** AWS CLI is not installed or not in PATH.

**Solution:**
```powershell
# Download and install AWS CLI v2 for Windows
# https://awscli.amazonaws.com/AWSCLIV2.msi

# Verify installation
aws --version

# Configure AWS credentials
aws configure
```

#### Error: Cannot parse JSON in PowerShell

**Problem:** JSON parsing fails due to special characters.

**Solution:**
The module's PowerShell scripts use proper JSON escaping. If you see errors:
```powershell
# Ensure AWS CLI output is valid JSON
aws sts get-caller-identity --output json

# Test jq installation
echo '{"test":"value"}' | jq .
```

### Unix/Linux/Mac-Specific Issues

#### Error: jq: command not found

**Problem:** jq is not installed.

**Solution:**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt update
sudo apt install jq

# RHEL/CentOS
sudo yum install jq

# Verify
jq --version
```

#### Error: Permission denied on script execution

**Problem:** Script files don't have execute permissions.

**Solution:**
The module uses `local-exec` provisioner which doesn't require execute permissions. If you manually run scripts:
```bash
chmod +x modules/account-factory/scripts/*.sh
```

### Common Issues (All Platforms)

#### Error: EMAIL_ALREADY_EXISTS

**Problem:** Email address is still in use by a suspended account.

**Solution:**
```bash
# Use a different email with + trick
developer_email = "john.smith+dev2@boseprofessional.com"
```

#### Error: Cannot assume OrganizationAccountAccessRole

**Problem:** Role hasn't propagated yet or credentials expired.

**Solution:**
```bash
# Simply run terraform apply again
terraform apply

# The module includes 60-second wait and retry logic
```

#### Debug: Enable Verbose Output

**Windows:**
```powershell
# Enable verbose output for AWS CLI
$env:AWS_DEBUG = "true"
terraform apply

# View PowerShell script execution
$VerbosePreference = "Continue"
```

**Unix/Linux/Mac:**
```bash
# Enable verbose output for AWS CLI
export AWS_DEBUG=1
terraform apply

# Enable bash debugging
export PS4='+ $(date "+%Y-%m-%d %H:%M:%S") ${BASH_SOURCE}:${LINENO}: '
set -x
```

## Script Directory Structure

```
modules/account-factory/
├── main.tf                              # Auto-detects OS and selects scripts
├── variables.tf
├── outputs.tf
├── templates/
│   ├── backend.tf.tpl
│   └── onboarding.md.tpl
└── scripts/
    ├── configure-account.ps1            # Windows PowerShell
    ├── configure-account.sh             # Unix/Linux/Mac Bash
    ├── create-permission-boundary.ps1   # Windows PowerShell
    ├── create-permission-boundary.sh    # Unix/Linux/Mac Bash
    ├── create-developer-role.ps1        # Windows PowerShell
    ├── create-developer-role.sh         # Unix/Linux/Mac Bash
    ├── create-budget.ps1                # Windows PowerShell
    └── create-budget.sh                 # Unix/Linux/Mac Bash
```

## Platform-Specific Script Features

### PowerShell Scripts (.ps1)
- Use `$ErrorActionPreference = "Stop"` for fail-fast behavior
- Proper error handling with try/catch blocks
- Clean environment variable cleanup in finally blocks
- Write-Host for colored output
- ConvertFrom-Json and ConvertTo-Json for JSON handling
- Temp file handling with [System.IO.Path]::GetTempFileName()

### Bash Scripts (.sh)
- Use `set -e` for fail-fast behavior
- Standard error handling with || echo for idempotent operations
- Environment variable export/cleanup
- Heredoc syntax for multi-line JSON
- /tmp directory for temporary files

## Testing on Both Platforms

### Windows Testing
```powershell
# Test OS detection
terraform console
> local.is_windows
true

# Test PowerShell availability
Get-Command pwsh -ErrorAction SilentlyContinue

# Dry run without applying
terraform plan
```

### Unix/Linux/Mac Testing
```bash
# Test OS detection
terraform console
> local.is_windows
false

# Test bash availability
which bash

# Dry run without applying
terraform plan
```

## Best Practices

### For Windows Users
1. **Use PowerShell 7+** for better compatibility (though 5.1 works)
2. **Run as regular user** (not Administrator) for security
3. **Enable script signing** in production environments
4. **Use Windows Terminal** for better console experience

### For Unix Users
1. **Use bash 4.0+** for better compatibility
2. **Ensure /bin/bash exists** (use `which bash` to verify)
3. **Keep jq updated** for latest features
4. **Use consistent line endings** (LF, not CRLF)

### For All Users
1. **Keep AWS CLI updated** to version 2.x
2. **Configure AWS credentials** properly before running
3. **Test in development** before production
4. **Review generated documentation** in `generated/` directory

## CI/CD Considerations

### GitHub Actions
```yaml
jobs:
  terraform:
    runs-on: ubuntu-latest  # or windows-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        
      - name: Install jq (Ubuntu)
        if: runner.os == 'Linux'
        run: sudo apt-get install -y jq
        
      - name: Install jq (Windows)
        if: runner.os == 'Windows'
        run: choco install jq
        
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
          
      - name: Terraform Apply
        run: terraform apply -auto-approve
```

### Azure DevOps
```yaml
steps:
  - task: TerraformInstaller@0
    inputs:
      terraformVersion: 'latest'
      
  - script: |
      # Install jq based on agent OS
      if [ "$(Agent.OS)" = "Linux" ]; then
        sudo apt-get install -y jq
      elif [ "$(Agent.OS)" = "Windows_NT" ]; then
        choco install jq -y
      fi
    displayName: 'Install jq'
    
  - task: TerraformTaskV2@2
    inputs:
      command: 'apply'
      environmentServiceNameAWS: 'AWS-Connection'
```

## Security Considerations

Both PowerShell and Bash scripts follow security best practices:

1. **Temporary credentials**: Use STS assume-role with session tokens
2. **Credential cleanup**: Remove environment variables after use
3. **Secure file handling**: Use system temp directories
4. **No credential logging**: Sensitive data not echoed to console
5. **Fail-fast behavior**: Stop on any error

## Future Enhancements

- [ ] Support for custom script paths
- [ ] WSL (Windows Subsystem for Linux) detection
- [ ] Alternative shells (zsh, fish) support
- [ ] Script validation and testing framework
- [ ] Progress indicators for long-running operations

## References

- [AWS Organizations Documentation](https://docs.aws.amazon.com/organizations/)
- [PowerShell Documentation](https://docs.microsoft.com/powershell/)
- [Bash Reference Manual](https://www.gnu.org/software/bash/manual/)
- [AWS CLI v2 Documentation](https://docs.aws.amazon.com/cli/latest/userguide/)
- [jq Manual](https://stedolan.github.io/jq/manual/)
