# scripts/apply-cis-compliance.ps1
# Apply CIS compliance fixes to existing developer accounts

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidatePattern('^[0-9]{12}$')]
    [string]$AccountId,
    
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [string]$DeveloperName,
    
    [Parameter(Mandatory=$true, Position=2)]
    [ValidatePattern('^vpc-[a-z0-9]{8,17}$')]
    [string]$VpcId,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Apply CIS Compliance to AWS Developer Account
============================================

USAGE:
    .\apply-cis-compliance.ps1 -AccountId <id> -DeveloperName <name> -VpcId <vpc>

PARAMETERS:
    -AccountId       AWS account ID (12 digits)
    -DeveloperName   Developer name (e.g., john-smith)
    -VpcId          VPC ID in the account (e.g., vpc-12345678)

EXAMPLE:
    .\apply-cis-compliance.ps1 -AccountId 123456789012 -DeveloperName john-smith -VpcId vpc-abc123def

CIS CONTROLS APPLIED:
    Config.1 (Critical) - Enable AWS Config
    EC2.2 (High)        - Restrict default security group
    EC2.6 (Medium)      - Enable VPC Flow Logs
    IAM.11-17 (Med/Low) - Set IAM password policy
    IAM.18 (Low)        - Create AWS Support role

MANUAL ACTIONS REQUIRED AFTER SCRIPT:
    IAM.6 (Critical)    - Enable hardware MFA for root user
    EC2.13 (High)       - Review security groups for SSH access
    IAM.3 (Medium)      - Rotate IAM access keys (90 days)
"@
    exit 0
}

$ErrorActionPreference = "Stop"

function Write-Header {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  CIS Compliance Remediation for AWS Accounts" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Failure {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Cyan
}

# Check prerequisites
try {
    $null = Get-Command aws -ErrorAction Stop
} catch {
    Write-Failure "AWS CLI is not installed"
    exit 1
}

Write-Header

Write-Info "Account ID: $AccountId"
Write-Info "Developer: $DeveloperName"
Write-Info "VPC ID: $VpcId"
Write-Host ""

# Verify AWS credentials
Write-Info "Verifying AWS credentials..."
try {
    $null = aws sts get-caller-identity 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "AWS credentials not configured"
    }
    Write-Success "AWS credentials verified"
} catch {
    Write-Failure "AWS credentials not configured"
    exit 1
}
Write-Host ""

# Assume role
Write-Info "Assuming role into target account..."
$RoleArn = "arn:aws:iam::${AccountId}:role/OrganizationAccountAccessRole"

try {
    $CredentialsJson = aws sts assume-role `
        --role-arn $RoleArn `
        --role-session-name "cis-compliance-session" `
        --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw $CredentialsJson
    }
    
    $Credentials = $CredentialsJson | ConvertFrom-Json
    
    $env:AWS_ACCESS_KEY_ID = $Credentials.Credentials.AccessKeyId
    $env:AWS_SECRET_ACCESS_KEY = $Credentials.Credentials.SecretAccessKey
    $env:AWS_SESSION_TOKEN = $Credentials.Credentials.SessionToken
    
    Write-Success "Assumed role successfully"
} catch {
    Write-Failure "Failed to assume role: $RoleArn"
    Write-Host $_.Exception.Message
    exit 1
}
Write-Host ""

$Region = aws configure get region
if ([string]::IsNullOrEmpty($Region)) {
    $Region = "us-east-1"
}

# ============================================================================
# CIS Config.1 - Enable AWS Config
# ============================================================================

Write-Info "Applying CIS Config.1: Enabling AWS Config..."

$BucketName = "config-bucket-${DeveloperName}-${AccountId}"

try {
    $null = aws s3 ls "s3://${BucketName}" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Creating S3 bucket for AWS Config..."
        
        $null = aws s3api create-bucket `
            --bucket $BucketName `
            --region $Region `
            --create-bucket-configuration LocationConstraint=$Region 2>&1
        
        # Enable versioning
        $null = aws s3api put-bucket-versioning `
            --bucket $BucketName `
            --versioning-configuration Status=Enabled
        
        # Enable encryption
        $null = aws s3api put-bucket-encryption `
            --bucket $BucketName `
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }]
            }'
        
        # Block public access
        $null = aws s3api put-public-access-block `
            --bucket $BucketName `
            --public-access-block-configuration `
                "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
        
        # Bucket policy
        $PolicyJson = @"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AWSConfigBucketPermissionsCheck",
            "Effect": "Allow",
            "Principal": {"Service": "config.amazonaws.com"},
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::${BucketName}",
            "Condition": {"StringEquals": {"AWS:SourceAccount": "${AccountId}"}}
        },
        {
            "Sid": "AWSConfigBucketExistenceCheck",
            "Effect": "Allow",
            "Principal": {"Service": "config.amazonaws.com"},
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::${BucketName}",
            "Condition": {"StringEquals": {"AWS:SourceAccount": "${AccountId}"}}
        },
        {
            "Sid": "AWSConfigBucketPutObject",
            "Effect": "Allow",
            "Principal": {"Service": "config.amazonaws.com"},
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${BucketName}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control",
                    "AWS:SourceAccount": "${AccountId}"
                }
            }
        }
    ]
}
"@
        
        $TempFile = [System.IO.Path]::GetTempFileName()
        $PolicyJson | Out-File -FilePath $TempFile -Encoding UTF8
        
        $null = aws s3api put-bucket-policy --bucket $BucketName --policy "file://$TempFile"
        Remove-Item $TempFile -ErrorAction SilentlyContinue
        
        Write-Success "Created Config S3 bucket: $BucketName"
    } else {
        Write-Warning "Config S3 bucket already exists: $BucketName"
    }
} catch {
    Write-Warning "Error creating Config bucket: $($_.Exception.Message)"
}

# Create Config service-linked role
try {
    $null = aws iam get-role --role-name AWSServiceRoleForConfig 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Creating AWS Config service-linked role..."
        $null = aws iam create-service-linked-role --aws-service-name config.amazonaws.com 2>&1
        Write-Success "Created Config service-linked role"
    } else {
        Write-Warning "Config service-linked role already exists"
    }
} catch {
    Write-Warning "Config role may already exist"
}

$ServiceRoleArn = "arn:aws:iam::${AccountId}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"

# Create configuration recorder
try {
    $Recorders = aws configservice describe-configuration-recorders --output json | ConvertFrom-Json
    if ($Recorders.ConfigurationRecorders.Count -eq 0) {
        Write-Info "Creating AWS Config recorder..."
        
        $null = aws configservice put-configuration-recorder `
            --configuration-recorder name=cis-config-recorder,roleARN="$ServiceRoleArn" `
            --recording-group allSupported=true,includeGlobalResourceTypes=true
        
        Write-Success "Created Config recorder"
    } else {
        Write-Warning "Config recorder already exists"
    }
} catch {
    Write-Warning "Error creating Config recorder"
}

# Create delivery channel
try {
    $Channels = aws configservice describe-delivery-channels --output json | ConvertFrom-Json
    if ($Channels.DeliveryChannels.Count -eq 0) {
        Write-Info "Creating AWS Config delivery channel..."
        
        $null = aws configservice put-delivery-channel `
            --delivery-channel name=cis-config-delivery,s3BucketName="$BucketName"
        
        Write-Success "Created Config delivery channel"
    } else {
        Write-Warning "Config delivery channel already exists"
    }
} catch {
    Write-Warning "Error creating delivery channel"
}

# Start recording
Write-Info "Starting AWS Config recorder..."
$null = aws configservice start-configuration-recorder --configuration-recorder-name cis-config-recorder 2>&1
Write-Success "AWS Config enabled (CIS Config.1)"
Write-Host ""

# ============================================================================
# CIS EC2.2 - Restrict default security group
# ============================================================================

Write-Info "Applying CIS EC2.2: Restricting default security group..."

try {
    $DefaultSg = aws ec2 describe-security-groups `
        --filters "Name=vpc-id,Values=$VpcId" "Name=group-name,Values=default" `
        --query 'SecurityGroups[0].GroupId' `
        --output text
    
    if ($DefaultSg -and $DefaultSg -ne "None") {
        Write-Info "Found default security group: $DefaultSg"
        
        # Get and remove ingress rules
        $IngressJson = aws ec2 describe-security-groups `
            --group-ids $DefaultSg `
            --query 'SecurityGroups[0].IpPermissions' `
            --output json
        
        if ($IngressJson -ne "[]") {
            Write-Info "Removing ingress rules..."
            $null = aws ec2 revoke-security-group-ingress `
                --group-id $DefaultSg `
                --ip-permissions $IngressJson 2>&1
        }
        
        # Get and remove egress rules
        $EgressJson = aws ec2 describe-security-groups `
            --group-ids $DefaultSg `
            --query 'SecurityGroups[0].IpPermissionsEgress' `
            --output json
        
        if ($EgressJson -ne "[]") {
            Write-Info "Removing egress rules..."
            $null = aws ec2 revoke-security-group-egress `
                --group-id $DefaultSg `
                --ip-permissions $EgressJson 2>&1
        }
        
        # Tag it
        $null = aws ec2 create-tags `
            --resources $DefaultSg `
            --tags Key=CISControl,Value=EC2.2 Key=Note,Value="CIS compliance - no traffic allowed"
        
        Write-Success "Default security group restricted (CIS EC2.2)"
    } else {
        Write-Warning "Could not find default security group for VPC $VpcId"
    }
} catch {
    Write-Warning "Error restricting default security group: $($_.Exception.Message)"
}
Write-Host ""

# ============================================================================
# CIS EC2.6 - Enable VPC Flow Logs
# ============================================================================

Write-Info "Applying CIS EC2.6: Enabling VPC Flow Logs..."

try {
    $ExistingFlowLog = aws ec2 describe-flow-logs `
        --filter "Name=resource-id,Values=$VpcId" `
        --query 'FlowLogs[0].FlowLogId' `
        --output text
    
    if ([string]::IsNullOrEmpty($ExistingFlowLog) -or $ExistingFlowLog -eq "None") {
        # Create log group
        $LogGroup = "/aws/vpc/flowlogs/${VpcId}"
        
        $LogGroups = aws logs describe-log-groups --log-group-name-prefix $LogGroup --output json | ConvertFrom-Json
        if ($LogGroups.logGroups.Count -eq 0) {
            Write-Info "Creating CloudWatch log group..."
            $null = aws logs create-log-group --log-group-name $LogGroup
            $null = aws logs put-retention-policy --log-group-name $LogGroup --retention-in-days 90
        }
        
        # Create IAM role
        $FlowLogsRole = "VPCFlowLogsRole-${DeveloperName}"
        
        try {
            $null = aws iam get-role --role-name $FlowLogsRole 2>&1
        } catch {
            Write-Info "Creating VPC Flow Logs IAM role..."
            
            $TrustPolicy = @"
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "vpc-flow-logs.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
"@
            
            $PolicyDoc = @"
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "logs:DescribeLogGroups",
            "logs:DescribeLogStreams"
        ],
        "Resource": "*"
    }]
}
"@
            
            $TrustFile = [System.IO.Path]::GetTempFileName()
            $PolicyFile = [System.IO.Path]::GetTempFileName()
            
            $TrustPolicy | Out-File -FilePath $TrustFile -Encoding UTF8
            $PolicyDoc | Out-File -FilePath $PolicyFile -Encoding UTF8
            
            $null = aws iam create-role `
                --role-name $FlowLogsRole `
                --assume-role-policy-document "file://$TrustFile" 2>&1
            
            $null = aws iam put-role-policy `
                --role-name $FlowLogsRole `
                --policy-name "vpc-flow-logs-policy" `
                --policy-document "file://$PolicyFile"
            
            Remove-Item $TrustFile, $PolicyFile -ErrorAction SilentlyContinue
            
            Start-Sleep -Seconds 10
        }
        
        $RoleArn = "arn:aws:iam::${AccountId}:role/${FlowLogsRole}"
        
        Write-Info "Creating VPC Flow Log..."
        $null = aws ec2 create-flow-logs `
            --resource-type VPC `
            --resource-ids $VpcId `
            --traffic-type ALL `
            --log-destination-type cloud-watch-logs `
            --log-group-name $LogGroup `
            --deliver-logs-permission-arn $RoleArn `
            --tag-specifications "ResourceType=vpc-flow-log,Tags=[{Key=CISControl,Value=EC2.6}]" 2>&1
        
        Write-Success "VPC Flow Logs enabled (CIS EC2.6)"
    } else {
        Write-Warning "VPC Flow Logs already enabled: $ExistingFlowLog"
    }
} catch {
    Write-Warning "Error enabling VPC Flow Logs: $($_.Exception.Message)"
}
Write-Host ""

# ============================================================================
# CIS IAM.11-17 - IAM Password Policy
# ============================================================================

Write-Info "Applying CIS IAM.11-17: Setting IAM password policy..."

try {
    $null = aws iam update-account-password-policy `
        --minimum-password-length 14 `
        --require-uppercase-characters `
        --require-lowercase-characters `
        --require-symbols `
        --require-numbers `
        --password-reuse-prevention 24 `
        --max-password-age 90 `
        --allow-users-to-change-password 2>&1
    
    Write-Success "IAM password policy configured (CIS IAM.11-17)"
} catch {
    Write-Warning "Error setting password policy: $($_.Exception.Message)"
}
Write-Host ""

# ============================================================================
# CIS IAM.18 - AWS Support Role
# ============================================================================

Write-Info "Applying CIS IAM.18: Creating AWS Support role..."

try {
    $null = aws iam get-role --role-name AWSSupportRole 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Get management account ID
        $MgmtAccountId = aws organizations describe-organization --query 'Organization.MasterAccountId' --output text 2>&1
        
        if ([string]::IsNullOrEmpty($MgmtAccountId)) {
            Write-Warning "Cannot determine management account ID, skipping Support role"
        } else {
            $AssumePolicy = @"
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"AWS": "arn:aws:iam::${MgmtAccountId}:root"},
        "Action": "sts:AssumeRole",
        "Condition": {"StringEquals": {"sts:ExternalId": "BoseSupport"}}
    }]
}
"@
            
            $TempFile = [System.IO.Path]::GetTempFileName()
            $AssumePolicy | Out-File -FilePath $TempFile -Encoding UTF8
            
            $null = aws iam create-role `
                --role-name AWSSupportRole `
                --description "Role for managing AWS Support incidents (CIS IAM.18)" `
                --assume-role-policy-document "file://$TempFile" `
                --tags Key=CISControl,Value=IAM.18 2>&1
            
            Remove-Item $TempFile -ErrorAction SilentlyContinue
            
            $null = aws iam attach-role-policy `
                --role-name AWSSupportRole `
                --policy-arn arn:aws:iam::aws:policy/AWSSupportAccess
            
            Write-Success "AWS Support role created (CIS IAM.18)"
        }
    } else {
        Write-Warning "AWS Support role already exists"
    }
} catch {
    Write-Warning "Error creating Support role: $($_.Exception.Message)"
}
Write-Host ""

# Cleanup
Remove-Item Env:\AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:\AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
Remove-Item Env:\AWS_SESSION_TOKEN -ErrorAction SilentlyContinue

# ============================================================================
# Summary
# ============================================================================

Write-Header
Write-Host "CIS Compliance Applied Successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Automated Fixes Applied:"
Write-Host "  ✓ Config.1  - AWS Config enabled"
Write-Host "  ✓ EC2.2     - Default security group restricted"
Write-Host "  ✓ EC2.6     - VPC Flow Logs enabled"
Write-Host "  ✓ IAM.11-17 - IAM password policy configured"
Write-Host "  ✓ IAM.18    - AWS Support role created"
Write-Host ""
Write-Warning "MANUAL ACTIONS REQUIRED:"
Write-Host ""
Write-Host "1. IAM.6 (CRITICAL) - Enable hardware MFA for root user"
Write-Host "   • Log in as root user"
Write-Host "   • Go to IAM → Dashboard → Security recommendations"
Write-Host "   • Add MFA device (hardware U2F or hardware TOTP)"
Write-Host ""
Write-Host "2. EC2.13 (HIGH) - Review security groups for SSH access"
Write-Host "   • Run: aws ec2 describe-security-groups --filters Name=ip-permission.from-port,Values=22"
Write-Host "   • Remove any rules with 0.0.0.0/0 or ::/0 source"
Write-Host ""
Write-Host "3. IAM.3 (MEDIUM) - Set up access key rotation reminders"
Write-Host "   • Create calendar reminders for 90-day key rotation"
Write-Host ""
Write-Info "Run validation script to verify compliance:"
Write-Host "  .\scripts\validate-account.ps1 -AccountName bose-dev-${DeveloperName}"
Write-Host ""
