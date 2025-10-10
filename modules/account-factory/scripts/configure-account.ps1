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

# ============================================================================
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

# ============================================================================
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
        Version = "2012-10-17"
        Statement = @(
            @{
                Effect = "Allow"
                Principal = @{
                    AWS = "arn:aws:iam::$($ManagementAccountId):root"
                }
                Action = "sts:AssumeRole"
            }
        )
    } | ConvertTo-Json -Depth 10
    
    $TrustPolicyFile = [System.IO.Path]::GetTempFileName()
    $TrustPolicy | Out-File -FilePath $TrustPolicyFile -Encoding UTF8
    
    # Create role
    aws iam create-role `
        --role-name DeveloperRole `
        --assume-role-policy-document "file://$TrustPolicyFile" `
        --permissions-boundary "arn:aws:iam::$($AccountId):policy/DeveloperPermissionBoundary" 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Role may already exist" -ForegroundColor Yellow
    } else {
        Write-Host "Developer role created successfully" -ForegroundColor Green
    }
    
    # Attach PowerUserAccess policy
    Write-Host "Attaching PowerUserAccess policy..." -ForegroundColor Green
    aws iam attach-role-policy `
        --role-name DeveloperRole `
        --policy-arn "arn:aws:iam::aws:policy/PowerUserAccess" 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Policy may already be attached" -ForegroundColor Yellow
    }
    
    # Clean up
    Remove-Item $TrustPolicyFile -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
} finally {
    Remove-Item Env:\AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
    Remove-Item Env:\AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
}

# ============================================================================
# modules/account-factory/scripts/create-budget.ps1
# Create AWS budget with alerts

$ErrorActionPreference = "Stop"

$AccountId = "${account_id}"
$DeveloperName = "${developer_name}"
$BudgetLimit = "${budget_limit}"
$DeveloperEmail = "${developer_email}"
$AdminEmail = "${admin_email}"

Write-Host "Creating budget..." -ForegroundColor Cyan

try {
    # Budget definition
    $Budget = @{
        BudgetName = "bose-dev-$DeveloperName-monthly-budget"
        BudgetType = "COST"
        TimeUnit = "MONTHLY"
        BudgetLimit = @{
            Amount = $BudgetLimit
            Unit = "USD"
        }
        CostFilters = @{
            LinkedAccount = @($AccountId)
        }
    } | ConvertTo-Json -Depth 10
    
    # Notifications
    $Notifications = @(
        @{
            Notification = @{
                NotificationType = "ACTUAL"
                ComparisonOperator = "GREATER_THAN"
                Threshold = 80
                ThresholdType = "PERCENTAGE"
            }
            Subscribers = @(
                @{
                    SubscriptionType = "EMAIL"
                    Address = $DeveloperEmail
                },
                @{
                    SubscriptionType = "EMAIL"
                    Address = $AdminEmail
                }
            )
        },
        @{
            Notification = @{
                NotificationType = "FORECASTED"
                ComparisonOperator = "GREATER_THAN"
                Threshold = 90
                ThresholdType = "PERCENTAGE"
            }
            Subscribers = @(
                @{
                    SubscriptionType = "EMAIL"
                    Address = $DeveloperEmail
                },
                @{
                    SubscriptionType = "EMAIL"
                    Address = $AdminEmail
                }
            )
        }
    ) | ConvertTo-Json -Depth 10
    
    # Save to temp files
    $BudgetFile = [System.IO.Path]::GetTempFileName()
    $NotificationsFile = [System.IO.Path]::GetTempFileName()
    
    $Budget | Out-File -FilePath $BudgetFile -Encoding UTF8
    $Notifications | Out-File -FilePath $NotificationsFile -Encoding UTF8
    
    # Create budget
    aws budgets create-budget `
        --account-id $AccountId `
        --budget "file://$BudgetFile" `
        --notifications-with-subscribers "file://$NotificationsFile" 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Budget may already exist" -ForegroundColor Yellow
    } else {
        Write-Host "Budget created successfully" -ForegroundColor Green
    }
    
    # Clean up
    Remove-Item $BudgetFile -ErrorAction SilentlyContinue
    Remove-Item $NotificationsFile -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
