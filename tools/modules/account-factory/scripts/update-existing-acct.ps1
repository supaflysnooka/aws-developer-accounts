# scripts/update-existing-acct.ps1
# Update existing developer account with latest permission boundary

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="AWS Account ID (12 digits)")]
    [ValidatePattern('^[0-9]{12}$')]
    [string]$AccountId,
    
    [Parameter(Mandatory=$true, Position=1, HelpMessage="Developer name (e.g., frank-caputo)")]
    [ValidateNotNullOrEmpty()]
    [string]$DeveloperName,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Display help if requested
if ($Help) {
    Write-Host @"
Update Existing Developer Account
==================================

Updates an existing developer account with the latest permission boundary policy.

USAGE:
    .\update-existing-acct.ps1 -AccountId <account-id> -DeveloperName <developer-name>

PARAMETERS:
    -AccountId       The AWS account ID (12 digits, e.g., 123456789012)
    -DeveloperName   The developer's name (e.g., frank-caputo)
    -Help            Display this help message

EXAMPLES:
    .\update-existing-acct.ps1 -AccountId 123456789012 -DeveloperName frank-caputo
    
    # Find account ID first, then update
    `$AccountId = aws organizations list-accounts --query "Accounts[?Name=='bose-dev-frank-caputo'].Id" --output text
    .\update-existing-acct.ps1 -AccountId `$AccountId -DeveloperName frank-caputo

REQUIREMENTS:
    - AWS CLI configured with appropriate credentials
    - Permissions to assume OrganizationAccountAccessRole
    - PowerShell 5.1 or PowerShell Core 7+
"@
    exit 0
}

$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Error', 'Success', 'Warning', 'Info')]
        [string]$Type = 'Info'
    )
    
    $color = switch ($Type) {
        'Error'   { 'Red' }
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Info'    { 'Cyan' }
    }
    
    $prefix = switch ($Type) {
        'Error'   { 'ERROR: ' }
        'Success' { '✓ ' }
        'Warning' { '⚠ ' }
        'Info'    { 'ℹ ' }
    }
    
    Write-Host "$prefix$Message" -ForegroundColor $color
}

# Check if AWS CLI is installed
try {
    $null = Get-Command aws -ErrorAction Stop
} catch {
    Write-ColorOutput "AWS CLI is not installed or not in PATH" -Type Error
    Write-Host "Install from: https://aws.amazon.com/cli/"
    exit 1
}

# Verify AWS credentials are configured
try {
    $null = aws sts get-caller-identity 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "AWS credentials not configured"
    }
} catch {
    Write-ColorOutput "AWS credentials not configured or expired" -Type Error
    Write-Host "Run: aws sso login --profile <your-profile>"
    exit 1
}

Write-ColorOutput "Updating account $AccountId for developer $DeveloperName..." -Type Info
Write-Host ""

# Define the role ARN
$RoleArn = "arn:aws:iam::${AccountId}:role/OrganizationAccountAccessRole"
$BoundaryName = "DeveloperPermissionsBoundary"
$BoundaryArn = "arn:aws:iam::${AccountId}:policy/${BoundaryName}"

Write-ColorOutput "Step 1: Assuming role into target account..." -Type Info
Write-Host "Role ARN: $RoleArn"

# Assume role and get credentials
try {
    $CredentialsJson = aws sts assume-role `
        --role-arn $RoleArn `
        --role-session-name "update-boundary-session" `
        --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw $CredentialsJson
    }
    
    $Credentials = $CredentialsJson | ConvertFrom-Json
    
    # Set temporary credentials
    $env:AWS_ACCESS_KEY_ID = $Credentials.Credentials.AccessKeyId
    $env:AWS_SECRET_ACCESS_KEY = $Credentials.Credentials.SecretAccessKey
    $env:AWS_SESSION_TOKEN = $Credentials.Credentials.SessionToken
    
    Write-ColorOutput "Successfully assumed role" -Type Success
    Write-Host ""
    
} catch {
    Write-ColorOutput "Failed to assume role" -Type Error
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Possible causes:"
    Write-Host "  1. OrganizationAccountAccessRole doesn't exist in target account"
    Write-Host "  2. You don't have permission to assume this role"
    Write-Host "  3. Account ID is incorrect"
    exit 1
}

# Define the permission boundary policy
$PolicyJson = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowedServices",
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "ec2:*",
        "lambda:*",
        "dynamodb:*",
        "rds:*",
        "cloudwatch:*",
        "logs:*",
        "sns:*",
        "sqs:*",
        "apigateway:*",
        "cloudformation:*",
        "secretsmanager:*",
        "kms:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "elasticache:*",
        "es:*",
        "kinesis:*",
        "firehose:*",
        "glue:*",
        "athena:*",
        "states:*",
        "batch:*",
        "ecs:*",
        "ecr:*",
        "eks:*",
        "comprehend:*",
        "rekognition:*",
        "textract:*",
        "translate:*",
        "polly:*",
        "transcribe:*",
        "lex:*",
        "sagemaker:*",
        "forecast:*",
        "personalize:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": [
            "us-east-1",
            "us-west-2"
          ]
        }
      }
    },
    {
      "Sid": "AllowIAMPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "lambda.amazonaws.com",
            "ec2.amazonaws.com",
            "ecs-tasks.amazonaws.com",
            "states.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "AllowIAMReadOnly",
      "Effect": "Allow",
      "Action": [
        "iam:Get*",
        "iam:List*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowLimitedIAMWrite",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:TagPolicy",
        "iam:UntagPolicy"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:PermissionsBoundary": "arn:aws:iam::${AccountId}:policy/DeveloperPermissionsBoundary"
        }
      }
    },
    {
      "Sid": "DenyPermissionBoundaryRemoval",
      "Effect": "Deny",
      "Action": [
        "iam:DeleteUserPermissionsBoundary",
        "iam:DeleteRolePermissionsBoundary"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyLeavingOrganization",
      "Effect": "Deny",
      "Action": [
        "organizations:LeaveOrganization"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyRootAccess",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:root"
        }
      }
    }
  ]
}
"@

# Replace the account ID placeholder
$PolicyJson = $PolicyJson.Replace('${AccountId}', $AccountId)

Write-ColorOutput "Step 2: Updating permission boundary policy..." -Type Info

# Save policy to temp file
$TempPolicy = [System.IO.Path]::GetTempFileName()
$PolicyJson | Out-File -FilePath $TempPolicy -Encoding UTF8

try {
    # Check if policy already exists
    $PolicyExists = $null
    try {
        $PolicyExists = aws iam list-policies --scope Local --query "Policies[?PolicyName=='$BoundaryName'].Arn" --output text 2>&1
    } catch {
        $PolicyExists = $null
    }
    
    if ([string]::IsNullOrWhiteSpace($PolicyExists)) {
        # Create new policy
        Write-ColorOutput "Creating new permission boundary policy..." -Type Info
        
        $CreateResult = aws iam create-policy `
            --policy-name $BoundaryName `
            --policy-document "file://$TempPolicy" `
            --description "Permission boundary for developer accounts - Updated $(Get-Date -Format 'yyyy-MM-dd')" `
            --output json 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "Permission boundary policy created" -Type Success
        } else {
            throw "Failed to create policy: $CreateResult"
        }
    } else {
        # Update existing policy
        Write-ColorOutput "Policy exists, creating new version..." -Type Info
        
        # Get current version count
        $VersionsJson = aws iam list-policy-versions `
            --policy-arn $BoundaryArn `
            --output json 2>&1
        
        $Versions = ($VersionsJson | ConvertFrom-Json).Versions
        $VersionCount = $Versions.Count
        
        # AWS allows max 5 versions, delete oldest non-default if at limit
        if ($VersionCount -ge 5) {
            Write-ColorOutput "Reached max policy versions (5), deleting oldest..." -Type Warning
            
            $OldestVersion = $Versions | 
                Where-Object { -not $_.IsDefaultVersion } | 
                Sort-Object CreateDate | 
                Select-Object -First 1 -ExpandProperty VersionId
            
            $null = aws iam delete-policy-version `
                --policy-arn $BoundaryArn `
                --version-id $OldestVersion 2>&1
            
            Write-ColorOutput "Deleted old policy version: $OldestVersion" -Type Success
        }
        
        # Create new policy version and set as default
        $UpdateResult = aws iam create-policy-version `
            --policy-arn $BoundaryArn `
            --policy-document "file://$TempPolicy" `
            --set-as-default `
            --output json 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "Permission boundary policy updated" -Type Success
        } else {
            throw "Failed to update policy: $UpdateResult"
        }
    }
    
} catch {
    Write-ColorOutput "Error updating permission boundary" -Type Error
    Write-Host $_.Exception.Message
    Remove-Item $TempPolicy -ErrorAction SilentlyContinue
    exit 1
} finally {
    Remove-Item $TempPolicy -ErrorAction SilentlyContinue
}

Write-Host ""
Write-ColorOutput "Step 3: Checking DeveloperRole permission boundary..." -Type Info

# Check if DeveloperRole exists
try {
    $RoleJson = aws iam get-role --role-name DeveloperRole --output json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $Role = $RoleJson | ConvertFrom-Json
        $CurrentBoundary = $Role.Role.PermissionsBoundary.PermissionsBoundaryArn
        
        if ($CurrentBoundary -eq $BoundaryArn) {
            Write-ColorOutput "DeveloperRole already has correct permission boundary" -Type Success
        } elseif ([string]::IsNullOrWhiteSpace($CurrentBoundary)) {
            Write-ColorOutput "Attaching permission boundary to DeveloperRole..." -Type Info
            
            $null = aws iam put-role-permissions-boundary `
                --role-name DeveloperRole `
                --permissions-boundary $BoundaryArn 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput "Permission boundary attached to DeveloperRole" -Type Success
            } else {
                Write-ColorOutput "Failed to attach permission boundary to DeveloperRole" -Type Error
                exit 1
            }
        } else {
            Write-ColorOutput "DeveloperRole has a different permission boundary: $CurrentBoundary" -Type Warning
            Write-Host "You may want to update it manually"
        }
    } else {
        Write-ColorOutput "DeveloperRole does not exist in this account" -Type Warning
        Write-Host "This is normal if the account was created without the standard DeveloperRole"
    }
} catch {
    Write-ColorOutput "DeveloperRole does not exist in this account" -Type Warning
    Write-Host "This is normal if the account was created without the standard DeveloperRole"
}

Write-Host ""
Write-ColorOutput "Account update completed successfully!" -Type Success
Write-Host ""
Write-ColorOutput "Summary:" -Type Info
Write-Host "  • Account ID: $AccountId"
Write-Host "  • Developer: $DeveloperName"
Write-Host "  • Boundary Policy: $BoundaryArn"
Write-Host "  • Role Status: $(if ($LASTEXITCODE -eq 0) { 'Updated' } else { 'Not found' })"
Write-Host ""

# Clean up credentials
Remove-Item Env:\AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:\AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
Remove-Item Env:\AWS_SESSION_TOKEN -ErrorAction SilentlyContinue

Write-ColorOutput "Next steps:" -Type Info
Write-Host "  1. Notify the developer that their account has been updated"
Write-Host "  2. They may need to log out and back in to get new permissions"
Write-Host "  3. Test that the new services are accessible"
