# modules/account-factory/scripts/create-developer-role.ps1
# Create developer IAM role

$ErrorActionPreference = "Stop"

$AccountId = "${account_id}"
$DeveloperName = "${developer_name}"
$ManagementAccountId = "${management_account_id}"

Write-Host "Creating developer role..." -ForegroundColor Cyan

try {
    # Assume role
    $CredsJson = aws sts assume-role `
        --role-arn "arn:aws:iam::$($AccountId):role/OrganizationAccountAccessRole" `
        --role-session-name "terraform-setup" `
        --output json
    
    $Creds = $CredsJson | ConvertFrom-Json
    
    $env:AWS_ACCESS_KEY_ID = $Creds.Credentials.AccessKeyId
    $env:AWS_SECRET_ACCESS_KEY = $Creds.Credentials.SecretAccessKey
    $env:AWS_SESSION_TOKEN = $Creds.Credentials.SessionToken
    
    # Create trust policy
    $TrustPolicy = @{
        Version   = "2012-10-17"
        Statement = @(
            @{
                Effect    = "Allow"
                Principal = @{
                    AWS = "arn:aws:iam::$($ManagementAccountId):root"
                }
                Action    = "sts:AssumeRole"
            }
        )
    } | ConvertTo-Json -Depth 10
    
    $TrustPolicyFile = [System.IO.Path]::GetTempFileName()
    $TrustPolicy | Out-File -FilePath $TrustPolicyFile -Encoding UTF8
    
    # Create role - allow it to fail if already exists
    $ErrorActionPreference = "Continue"
    aws iam create-role `
        --role-name DeveloperRole `
        --assume-role-policy-document "file://$TrustPolicyFile" `
        --permissions-boundary "arn:aws:iam::$($AccountId):policy/DeveloperPermissionBoundary" 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Role may already exist, continuing..." -ForegroundColor Yellow
    }
    else {
        Write-Host "  Developer role created successfully" -ForegroundColor Green
    }
    $ErrorActionPreference = "Stop"
    
    # Attach PowerUserAccess policy
    Write-Host "Attaching PowerUserAccess policy..." -ForegroundColor Green
    $ErrorActionPreference = "Continue"
    aws iam attach-role-policy `
        --role-name DeveloperRole `
        --policy-arn "arn:aws:iam::aws:policy/PowerUserAccess" 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Policy may already be attached, continuing..." -ForegroundColor Yellow
    }
    else {
        Write-Host "  Policy attached successfully" -ForegroundColor Green
    }
    $ErrorActionPreference = "Stop"
    
    # Clean up
    Remove-Item $TrustPolicyFile -ErrorAction SilentlyContinue
    
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
finally {
    Remove-Item Env:\AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
    Remove-Item Env:\AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
}