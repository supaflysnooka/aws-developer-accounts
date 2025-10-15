# AWS Organizations Configuration
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # Configure backend after terraform-backend is deployed
  # backend "s3" {
  #   bucket         = "your-bucket-name"
  #   key            = "bootstrap/organization/terraform.tfstate"
  #   region         = "us-east-2"
  #   dynamodb_table = "terraform-state-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region
}

# Create or import existing AWS Organization
resource "aws_organizations_organization" "main" {
  aws_service_access_principals = var.aws_service_access_principals
  
  enabled_policy_types = var.enabled_policy_types
  
  feature_set = var.feature_set
}

# Root OU is created automatically, but we reference it
data "aws_organizations_organization" "current" {
  depends_on = [aws_organizations_organization.main]
}

# Create Organizational Units
resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.main.roots[0].id
  
  tags = {
    Name        = "Security"
    Purpose     = "Security and compliance accounts"
    ManagedBy   = "terraform"
  }
}

resource "aws_organizations_organizational_unit" "infrastructure" {
  name      = "Infrastructure"
  parent_id = aws_organizations_organization.main.roots[0].id
  
  tags = {
    Name        = "Infrastructure"
    Purpose     = "Shared infrastructure services"
    ManagedBy   = "terraform"
  }
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.main.roots[0].id
  
  tags = {
    Name        = "Workloads"
    Purpose     = "Application and workload accounts"
    ManagedBy   = "terraform"
  }
}

# Create sub-OUs under Workloads
resource "aws_organizations_organizational_unit" "production" {
  name      = "Production"
  parent_id = aws_organizations_organizational_unit.workloads.id
  
  tags = {
    Name        = "Production"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_organizations_organizational_unit" "staging" {
  name      = "Staging"
  parent_id = aws_organizations_organizational_unit.workloads.id
  
  tags = {
    Name        = "Staging"
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}

resource "aws_organizations_organizational_unit" "development" {
  name      = "Development"
  parent_id = aws_organizations_organizational_unit.workloads.id
  
  tags = {
    Name        = "Development"
    Environment = "development"
    ManagedBy   = "terraform"
  }
}

resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "Sandbox"
  parent_id = aws_organizations_organization.main.roots[0].id
  
  tags = {
    Name        = "Sandbox"
    Purpose     = "Experimentation and testing"
    ManagedBy   = "terraform"
  }
}

# Service Control Policies
# Deny leaving organization
resource "aws_organizations_policy" "deny_leave_organization" {
  name        = "DenyLeaveOrganization"
  description = "Prevents accounts from leaving the organization"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyLeaveOrganization"
        Effect   = "Deny"
        Action   = "organizations:LeaveOrganization"
        Resource = "*"
      }
    ]
  })
  
  tags = {
    Name      = "DenyLeaveOrganization"
    ManagedBy = "terraform"
  }
}

# Require MFA for sensitive operations
resource "aws_organizations_policy" "require_mfa" {
  name        = "RequireMFAForSensitiveOperations"
  description = "Requires MFA for sensitive API operations"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyActionsWithoutMFA"
        Effect = "Deny"
        Action = [
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "rds:DeleteDBInstance",
          "rds:DeleteDBCluster",
          "s3:DeleteBucket"
        ]
        Resource = "*"
        Condition = {
          BoolIfExists = {
            "aws:MultiFactorAuthPresent" = "false"
          }
        }
      }
    ]
  })
  
  tags = {
    Name      = "RequireMFAForSensitiveOperations"
    ManagedBy = "terraform"
  }
}

# Deny root user access
resource "aws_organizations_policy" "deny_root_user" {
  name        = "DenyRootUserAccess"
  description = "Denies all actions by root user except account management"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyRootUser"
        Effect = "Deny"
        Action = "*"
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:root"
          }
        }
      }
    ]
  })
  
  tags = {
    Name      = "DenyRootUserAccess"
    ManagedBy = "terraform"
  }
}

# Require encryption for S3
resource "aws_organizations_policy" "require_s3_encryption" {
  name        = "RequireS3Encryption"
  description = "Requires encryption for S3 buckets and objects"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyUnencryptedS3Uploads"
        Effect = "Deny"
        Action = "s3:PutObject"
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = ["AES256", "aws:kms"]
          }
        }
      },
      {
        Sid    = "DenyUnencryptedS3Buckets"
        Effect = "Deny"
        Action = "s3:CreateBucket"
        Resource = "*"
      }
    ]
  })
  
  tags = {
    Name      = "RequireS3Encryption"
    ManagedBy = "terraform"
  }
}

# Restrict regions (optional - customize as needed)
resource "aws_organizations_policy" "restrict_regions" {
  count = var.restrict_regions ? 1 : 0
  
  name        = "RestrictRegions"
  description = "Restricts AWS operations to approved regions"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyAllOutsideApprovedRegions"
        Effect = "Deny"
        NotAction = [
          "iam:*",
          "organizations:*",
          "route53:*",
          "budgets:*",
          "waf:*",
          "cloudfront:*",
          "globalaccelerator:*",
          "importexport:*",
          "support:*",
          "sts:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = var.approved_regions
          }
        }
      }
    ]
  })
  
  tags = {
    Name      = "RestrictRegions"
    ManagedBy = "terraform"
  }
}

# Attach SCPs to OUs
# Attach to root (applies to all accounts)
resource "aws_organizations_policy_attachment" "deny_leave_root" {
  policy_id = aws_organizations_policy.deny_leave_organization.id
  target_id = aws_organizations_organization.main.roots[0].id
}

# Attach MFA requirement to production
resource "aws_organizations_policy_attachment" "require_mfa_production" {
  policy_id = aws_organizations_policy.require_mfa.id
  target_id = aws_organizations_organizational_unit.production.id
}

# Attach encryption requirement to all workloads
resource "aws_organizations_policy_attachment" "require_s3_encryption_workloads" {
  policy_id = aws_organizations_policy.require_s3_encryption.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

# Attach root user restriction to production
resource "aws_organizations_policy_attachment" "deny_root_production" {
  policy_id = aws_organizations_policy.deny_root_user.id
  target_id = aws_organizations_organizational_unit.production.id
}

# Attach region restriction if enabled
resource "aws_organizations_policy_attachment" "restrict_regions_root" {
  count = var.restrict_regions ? 1 : 0
  
  policy_id = aws_organizations_policy.restrict_regions[0].id
  target_id = aws_organizations_organization.main.roots[0].id
}

# Enable AWS Config across the organization
resource "aws_organizations_policy" "enable_aws_config" {
  count = var.enable_aws_config ? 1 : 0
  
  name        = "EnableAWSConfig"
  description = "Requires AWS Config to be enabled"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDisableConfig"
        Effect = "Deny"
        Action = [
          "config:DeleteConfigRule",
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel",
          "config:StopConfigurationRecorder"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = {
    Name      = "EnableAWSConfig"
    ManagedBy = "terraform"
  }
}

resource "aws_organizations_policy_attachment" "enable_aws_config_root" {
  count = var.enable_aws_config ? 1 : 0
  
  policy_id = aws_organizations_policy.enable_aws_config[0].id
  target_id = aws_organizations_organization.main.roots[0].id
}

# CloudTrail protection
resource "aws_organizations_policy" "protect_cloudtrail" {
  count = var.protect_cloudtrail ? 1 : 0
  
  name        = "ProtectCloudTrail"
  description = "Prevents disabling or deletion of CloudTrail"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyCloudTrailDisable"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = {
    Name      = "ProtectCloudTrail"
    ManagedBy = "terraform"
  }
}

resource "aws_organizations_policy_attachment" "protect_cloudtrail_root" {
  count = var.protect_cloudtrail ? 1 : 0
  
  policy_id = aws_organizations_policy.protect_cloudtrail[0].id
  target_id = aws_organizations_organization.main.roots[0].id
}
