# modules/account-factory/scripts/create-permission-boundary.ps1
# Create IAM permission boundary policy

$ErrorActionPreference = "Stop"

$AccountId = "${account_id}"
$DeveloperName = "${developer_name}"
$PolicyJson = @'
${policy_json}
'@

Write-Host "Creating permission boundary policy..." -ForegroundColor Cyan

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
    
    # Save policy to temp file
    $TempFile = [System.IO.Path]::GetTempFileName()
    $PolicyJson | Out-File -FilePath $TempFile -Encoding UTF8
    
    # Create policy
    aws iam create-policy `
        --policy-name DeveloperPermissionBoundary `
        --policy-document "file://$TempFile" `
        --description "Permission boundary for developer accounts" 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Policy may already exist" -ForegroundColor Yellow
    } else {
        Write-Host "Permission boundary created successfully" -ForegroundColor Green
    }
    
    # Clean up temp file
    Remove-Item $TempFile -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
} finally {
    Remove-Item Env:\AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
    Remove-Item Env:\AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
}
