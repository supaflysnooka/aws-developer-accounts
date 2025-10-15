# modules/account-factory/scripts/configure-account.ps1
# Configure account resources using AWS CLI with assumed role

$ErrorActionPreference = "Stop"

$AccountId = "${account_id}"
$DeveloperName = "${developer_name}"
$AwsRegion = "${aws_region}"

Write-Host "Assuming role in account $AccountId..." -ForegroundColor Cyan

try {
    # Assume role and get credentials
    $CredsJson = aws sts assume-role `
        --role-arn "arn:aws:iam::$($AccountId):role/OrganizationAccountAccessRole" `
        --role-session-name "terraform-setup" `
        --duration-seconds 3600 `
        --output json
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to assume role"
    }
    
    $Creds = $CredsJson | ConvertFrom-Json
    
    # Set temporary credentials as environment variables
    $env:AWS_ACCESS_KEY_ID = $Creds.Credentials.AccessKeyId
    $env:AWS_SECRET_ACCESS_KEY = $Creds.Credentials.SecretAccessKey
    $env:AWS_SESSION_TOKEN = $Creds.Credentials.SessionToken
    
    Write-Host "Creating S3 bucket..." -ForegroundColor Green
    
    # Create S3 bucket
    $BucketName = "bose-dev-$DeveloperName-terraform-state"
    
    if ($AwsRegion -eq "us-east-1") {
        aws s3api create-bucket --bucket $BucketName --region $AwsRegion 2>$null
    } else {
        aws s3api create-bucket `
            --bucket $BucketName `
            --region $AwsRegion `
            --create-bucket-configuration LocationConstraint=$AwsRegion 2>$null
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Bucket may already exist" -ForegroundColor Yellow
    }
    
    Write-Host "Enabling versioning..." -ForegroundColor Green
    aws s3api put-bucket-versioning `
        --bucket $BucketName `
        --versioning-configuration Status=Enabled
    
    Write-Host "Enabling encryption..." -ForegroundColor Green
    $EncryptionConfig = @{
        Rules = @(
            @{
                ApplyServerSideEncryptionByDefault = @{
                    SSEAlgorithm = "AES256"
                }
            }
        )
    } | ConvertTo-Json -Depth 10 -Compress
    
    aws s3api put-bucket-encryption `
        --bucket $BucketName `
        --server-side-encryption-configuration $EncryptionConfig
    
    Write-Host "Blocking public access..." -ForegroundColor Green
    aws s3api put-public-access-block `
        --bucket $BucketName `
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    Write-Host "Creating DynamoDB table..." -ForegroundColor Green
    aws dynamodb create-table `
        --table-name "bose-dev-$DeveloperName-terraform-locks" `
        --attribute-definitions AttributeName=LockID,AttributeType=S `
        --key-schema AttributeName=LockID,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST `
        --region $AwsRegion 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Table may already exist" -ForegroundColor Yellow
    }
    
    Write-Host "Account configuration complete!" -ForegroundColor Green
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
} finally {
    # Clean up environment variables
    Remove-Item Env:\AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
    Remove-Item Env:\AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
}
