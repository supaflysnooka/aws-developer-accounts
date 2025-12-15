# scripts/validate-account.ps1
# Validate developer account configuration and compliance

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Account name (e.g., bose-dev-frank-caputo)")]
    [ValidateNotNullOrEmpty()]
    [string]$AccountName,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose,
    
    [Parameter(Mandatory=$false)]
    [switch]$Json,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Display help if requested
if ($Help) {
    Write-Host @"
Validate Developer Account Configuration
========================================

Validates that a developer account is properly configured and compliant.

USAGE:
    .\validate-account.ps1 -AccountName <account-name> [OPTIONS]

PARAMETERS:
    -AccountName    Name of the developer account (e.g., bose-dev-frank-caputo)
    -Verbose        Show detailed check results
    -Json           Output results in JSON format
    -Help           Show this help message

EXAMPLES:
    .\validate-account.ps1 -AccountName bose-dev-frank-caputo
    .\validate-account.ps1 -AccountName bose-dev-frank-caputo -Verbose
    .\validate-account.ps1 -AccountName bose-dev-frank-caputo -Json | Out-File results.json

CHECKS PERFORMED:
    ✓ Account exists in AWS Organizations
    ✓ Account is in correct Organizational Unit
    ✓ Permission boundary policy exists
    ✓ DeveloperRole exists and has boundary attached
    ✓ Budget is configured
    ✓ Required tags are present
    ✓ OrganizationAccountAccessRole exists

EXIT CODES:
    0 - All checks passed
    1 - One or more checks failed
    2 - Script error (invalid arguments, missing tools, etc.)
"@
    exit 0
}

$ErrorActionPreference = "Stop"

# Counters
$Script:Passed = 0
$Script:Failed = 0
$Script:Warnings = 0
$Script:Results = @()

# Helper functions
function Write-Check {
    param([string]$Message)
    if (-not $Json) {
        Write-Host "  Checking $Message... " -NoNewline
    }
}

function Write-Pass {
    param([string]$Details = "")
    $Script:Passed++
    if (-not $Json) {
        Write-Host "✓ PASS" -ForegroundColor Green
        if ($Verbose -and $Details) {
            Write-Host "    └─ $Details" -ForegroundColor Gray
        }
    }
}

function Write-Fail {
    param([string]$Details = "")
    $Script:Failed++
    if (-not $Json) {
        Write-Host "✗ FAIL" -ForegroundColor Red
        if ($Details) {
            Write-Host "    └─ $Details" -ForegroundColor Gray
        }
    }
}

function Write-Warning {
    param([string]$Details = "")
    $Script:Warnings++
    if (-not $Json) {
        Write-Host "⚠ WARNING" -ForegroundColor Yellow
        if ($Details) {
            Write-Host "    └─ $Details" -ForegroundColor Gray
        }
    }
}

function Add-Result {
    param(
        [string]$CheckName,
        [string]$Status,
        [string]$Message
    )
    
    $Script:Results += [PSCustomObject]@{
        Check = $CheckName
        Status = $Status
        Message = $Message
    }
}

# Check if AWS CLI is installed
try {
    $null = Get-Command aws -ErrorAction Stop
} catch {
    Write-Host "ERROR: AWS CLI is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Install from: https://aws.amazon.com/cli/"
    exit 2
}

# Verify AWS credentials
try {
    $null = aws sts get-caller-identity 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "AWS credentials not configured"
    }
} catch {
    Write-Host "ERROR: AWS credentials not configured or expired" -ForegroundColor Red
    Write-Host "Run: aws sso login --profile <your-profile>"
    exit 2
}

if (-not $Json) {
    Write-Host "Validating account: $AccountName" -ForegroundColor Cyan
    Write-Host ""
}

# Check 1: Account exists in AWS Organizations
if (-not $Json) {
    Write-Host "Organization Checks:" -ForegroundColor Cyan
}

Write-Check "Account exists in AWS Organizations"
try {
    $AccountJson = aws organizations list-accounts --query "Accounts[?Name=='$AccountName']" --output json 2>&1 | ConvertFrom-Json
    
    if ($AccountJson.Count -gt 0) {
        $AccountId = $AccountJson[0].Id
        $AccountStatus = $AccountJson[0].Status
        Write-Pass "Account ID: $AccountId, Status: $AccountStatus"
        Add-Result -CheckName "account_exists" -Status "PASS" -Message "Account ID: $AccountId, Status: $AccountStatus"
    } else {
        Write-Fail "Account not found in AWS Organizations"
        Add-Result -CheckName "account_exists" -Status "FAIL" -Message "Account not found in AWS Organizations"
        
        if (-not $Json) {
            Write-Host ""
            Write-Host "Validation failed - account does not exist" -ForegroundColor Red
        }
        exit 1
    }
} catch {
    Write-Fail "Error querying AWS Organizations: $($_.Exception.Message)"
    Add-Result -CheckName "account_exists" -Status "FAIL" -Message "Error querying AWS Organizations"
    exit 2
}

# Check 2: Account organizational unit
Write-Check "Account organizational unit"
try {
    $ParentId = aws organizations list-parents --child-id $AccountId --query 'Parents[0].Id' --output text 2>&1
    
    if ($ParentId -and $ParentId -ne "None") {
        $OuName = aws organizations describe-organizational-unit --organizational-unit-id $ParentId --query 'OrganizationalUnit.Name' --output text 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Pass "OU: $OuName ($ParentId)"
            Add-Result -CheckName "organizational_unit" -Status "PASS" -Message "OU: $OuName"
        } else {
            Write-Warning "Could not determine OU name"
            Add-Result -CheckName "organizational_unit" -Status "WARNING" -Message "Could not determine OU name"
        }
    } else {
        Write-Warning "Could not determine organizational unit"
        Add-Result -CheckName "organizational_unit" -Status "WARNING" -Message "Could not determine OU"
    }
} catch {
    Write-Warning "Error checking organizational unit"
    Add-Result -CheckName "organizational_unit" -Status "WARNING" -Message "Error checking OU"
}

if (-not $Json) {
    Write-Host ""
    Write-Host "IAM Checks:" -ForegroundColor Cyan
}

# Check 3: OrganizationAccountAccessRole exists
Write-Check "OrganizationAccountAccessRole exists"
$RoleArn = "arn:aws:iam::${AccountId}:role/OrganizationAccountAccessRole"

try {
    $CredentialsJson = aws sts assume-role `
        --role-arn $RoleArn `
        --role-session-name "validation-session" `
        --output json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $Credentials = $CredentialsJson | ConvertFrom-Json
        Write-Pass "Role is assumable"
        Add-Result -CheckName "org_access_role" -Status "PASS" -Message "OrganizationAccountAccessRole exists and is assumable"
        
        # Set temporary credentials
        $env:AWS_ACCESS_KEY_ID = $Credentials.Credentials.AccessKeyId
        $env:AWS_SECRET_ACCESS_KEY = $Credentials.Credentials.SecretAccessKey
        $env:AWS_SESSION_TOKEN = $Credentials.Credentials.SessionToken
        
        # Check 4: Permission boundary policy exists
        Write-Check "DeveloperPermissionsBoundary policy exists"
        $BoundaryArn = "arn:aws:iam::${AccountId}:policy/DeveloperPermissionsBoundary"
        
        try {
            $PolicyArn = aws iam get-policy --policy-arn $BoundaryArn --query 'Policy.Arn' --output text 2>&1
            
            if ($LASTEXITCODE -eq 0 -and $PolicyArn -eq $BoundaryArn) {
                Write-Pass "Policy exists"
                Add-Result -CheckName "permission_boundary_policy" -Status "PASS" -Message "DeveloperPermissionsBoundary policy exists"
            } else {
                Write-Fail "Permission boundary policy not found"
                Add-Result -CheckName "permission_boundary_policy" -Status "FAIL" -Message "DeveloperPermissionsBoundary policy not found"
            }
        } catch {
            Write-Fail "Permission boundary policy not found"
            Add-Result -CheckName "permission_boundary_policy" -Status "FAIL" -Message "DeveloperPermissionsBoundary policy not found"
        }
        
        # Check 5: DeveloperRole exists and has boundary
        Write-Check "DeveloperRole exists"
        try {
            $RoleJson = aws iam get-role --role-name DeveloperRole --output json 2>&1 | ConvertFrom-Json
            
            if ($RoleJson.Role) {
                $RoleBoundary = $RoleJson.Role.PermissionsBoundary.PermissionsBoundaryArn
                
                if ($RoleBoundary -eq $BoundaryArn) {
                    Write-Pass "Role has correct permission boundary"
                    Add-Result -CheckName "developer_role" -Status "PASS" -Message "DeveloperRole has correct permission boundary"
                } elseif (-not $RoleBoundary) {
                    Write-Fail "DeveloperRole exists but has no permission boundary"
                    Add-Result -CheckName "developer_role" -Status "FAIL" -Message "DeveloperRole missing permission boundary"
                } else {
                    Write-Warning "DeveloperRole has different boundary: $RoleBoundary"
                    Add-Result -CheckName "developer_role" -Status "WARNING" -Message "DeveloperRole has unexpected boundary"
                }
            } else {
                Write-Warning "DeveloperRole does not exist"
                Add-Result -CheckName "developer_role" -Status "WARNING" -Message "DeveloperRole not found (may not be required)"
            }
        } catch {
            Write-Warning "DeveloperRole does not exist"
            Add-Result -CheckName "developer_role" -Status "WARNING" -Message "DeveloperRole not found (may not be required)"
        }
        
        if (-not $Json) {
            Write-Host ""
            Write-Host "Budget Checks:" -ForegroundColor Cyan
        }
        
        # Check 6: Budget exists
        Write-Check "Budget configuration"
        try {
            $BudgetsJson = aws budgets describe-budgets --account-id $AccountId --output json 2>&1 | ConvertFrom-Json
            
            if ($BudgetsJson.Budgets -and $BudgetsJson.Budgets.Count -gt 0) {
                $BudgetCount = $BudgetsJson.Budgets.Count
                $BudgetAmount = $BudgetsJson.Budgets[0].BudgetLimit.Amount
                Write-Pass "Found $BudgetCount budget(s), Limit: `$$BudgetAmount"
                Add-Result -CheckName "budget" -Status "PASS" -Message "Budget configured with limit: `$$BudgetAmount"
            } else {
                Write-Warning "No budgets configured"
                Add-Result -CheckName "budget" -Status "WARNING" -Message "No budgets found"
            }
        } catch {
            Write-Warning "No budgets configured"
            Add-Result -CheckName "budget" -Status "WARNING" -Message "No budgets found"
        }
        
        if (-not $Json) {
            Write-Host ""
            Write-Host "Tagging Checks:" -ForegroundColor Cyan
        }
        
        # Check 7: Required tags
        Write-Check "Account tags"
        try {
            $TagsJson = aws organizations list-tags-for-resource --resource-id $AccountId --output json 2>&1 | ConvertFrom-Json
            
            if ($TagsJson.Tags -and $TagsJson.Tags.Count -gt 0) {
                $TagCount = $TagsJson.Tags.Count
                
                # Check for required tags
                $RequiredTags = @("Environment", "Owner", "CreatedBy")
                $MissingTags = @()
                
                foreach ($tag in $RequiredTags) {
                    if (-not ($TagsJson.Tags | Where-Object { $_.Key -eq $tag })) {
                        $MissingTags += $tag
                    }
                }
                
                if ($MissingTags.Count -eq 0) {
                    Write-Pass "All required tags present ($TagCount total)"
                    Add-Result -CheckName "tags" -Status "PASS" -Message "All required tags present"
                } else {
                    Write-Warning "Missing tags: $($MissingTags -join ', ')"
                    Add-Result -CheckName "tags" -Status "WARNING" -Message "Missing recommended tags: $($MissingTags -join ', ')"
                }
            } else {
                Write-Warning "No tags found on account"
                Add-Result -CheckName "tags" -Status "WARNING" -Message "No tags found"
            }
        } catch {
            Write-Warning "Could not retrieve account tags"
            Add-Result -CheckName "tags" -Status "WARNING" -Message "Could not retrieve tags"
        }
        
        # Clean up credentials
        Remove-Item Env:\AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
        Remove-Item Env:\AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
        Remove-Item Env:\AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
    } else {
        Write-Fail "Cannot assume OrganizationAccountAccessRole"
        Add-Result -CheckName "org_access_role" -Status "FAIL" -Message "Cannot assume OrganizationAccountAccessRole"
        
        if (-not $Json) {
            Write-Host "    └─ Cannot perform in-account checks without role access" -ForegroundColor Gray
        }
    }
} catch {
    Write-Fail "Cannot assume OrganizationAccountAccessRole"
    Add-Result -CheckName "org_access_role" -Status "FAIL" -Message "Cannot assume OrganizationAccountAccessRole"
}

# Summary
if ($Json) {
    # Output JSON results
    $Output = [PSCustomObject]@{
        account_name = $AccountName
        account_id = $AccountId
        timestamp = Get-Date -Format "o"
        summary = [PSCustomObject]@{
            passed = $Script:Passed
            failed = $Script:Failed
            warnings = $Script:Warnings
            total = $Script:Passed + $Script:Failed + $Script:Warnings
        }
        checks = $Script:Results
    }
    
    $Output | ConvertTo-Json -Depth 10
} else {
    Write-Host ""
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "Validation Summary" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "Passed:   " -NoNewline
    Write-Host $Script:Passed -ForegroundColor Green
    Write-Host "Failed:   " -NoNewline
    Write-Host $Script:Failed -ForegroundColor Red
    Write-Host "Warnings: " -NoNewline
    Write-Host $Script:Warnings -ForegroundColor Yellow
    Write-Host "================================" -ForegroundColor Cyan
    
    if ($Script:Failed -eq 0) {
        Write-Host "✓ Account validation successful" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "✗ Account validation failed" -ForegroundColor Red
        Write-Host ""
        Write-Host "Run with -Verbose flag for more details"
        exit 1
    }
}
