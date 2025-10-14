# Additional Service Control Policies
# This module provides a library of reusable SCPs that can be selectively applied
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # backend "s3" {
  #   bucket         = "your-bucket-name"
  #   key            = "bootstrap/scp-policies/terraform.tfstate"
  #   region         = "us-west-2"
  #   dynamodb_table = "terraform-state-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region
}

# Data source for organization
data "aws_organizations_organization" "current" {}

# ============================================================================
# COMPUTE RESTRICTIONS
# ============================================================================

# Restrict EC2 instance types
resource "aws_organizations_policy" "restrict_instance_types" {
  count = var.enable_instance_type_restrictions ? 1 : 0
  
  name        = "RestrictEC2InstanceTypes"
  description = "Restricts EC2 instances to approved instance types"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequireApprovedInstanceTypes"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "ec2:StartInstances"
        ]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringNotLike = {
            "ec2:InstanceType" = var.allowed_instance_types
          }
        }
      }
    ]
  })
  
  tags = var.tags
}

# Require IMDSv2 for EC2
resource "aws_organizations_policy" "require_imdsv2" {
  count = var.require_imdsv2 ? 1 : 0
  
  name        = "RequireIMDSv2"
  description = "Requires Instance Metadata Service Version 2 for EC2"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequireImdsV2"
        Effect = "Deny"
        Action = "ec2:RunInstances"
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringNotEquals = {
            "ec2:MetadataHttpTokens" = "required"
          }
        }
      }
    ]
  })
  
  tags = var.tags
}

# ============================================================================
# STORAGE AND DATA PROTECTION
# ============================================================================

# Require EBS encryption
resource "aws_organizations_policy" "require_ebs_encryption" {
  count = var.require_ebs_encryption ? 1 : 0
  
  name        = "RequireEBSEncryption"
  description = "Requires encryption for all EBS volumes"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyUnencryptedEBSVolumes"
        Effect = "Deny"
        Action = [
          "ec2:CreateVolume",
          "ec2:RunInstances"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "ec2:Encrypted" = "false"
          }
        }
      }
    ]
  })
  
  tags = var.tags
}

# Deny S3 bucket deletion
resource "aws_organizations_policy" "deny_s3_deletion" {
  count = var.protect_s3_buckets ? 1 : 0
  
  name        = "DenyS3BucketDeletion"
  description = "Prevents deletion of S3 buckets"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyBucketDeletion"
        Effect = "Deny"
        Action = [
          "s3:DeleteBucket",
          "s3:DeleteBucketPolicy",
          "s3:DeleteBucketWebsite",
          "s3:PutLifecycleConfiguration"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = var.tags
}

# Require S3 versioning
resource "aws_organizations_policy" "require_s3_versioning" {
  count = var.require_s3_versioning ? 1 : 0
  
  name        = "RequireS3Versioning"
  description = "Requires versioning for S3 buckets"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyPutBucketWithoutVersioning"
        Effect = "Deny"
        Action = "s3:CreateBucket"
        Resource = "*"
      },
      {
        Sid    = "DenyDeleteVersioning"
        Effect = "Deny"
        Action = "s3:PutBucketVersioning"
        Resource = "*"
        Condition = {
          StringEquals = {
            "s3:VersioningStatus" = "Suspended"
          }
        }
      }
    ]
  })
  
  tags = var.tags
}

# ============================================================================
# DATABASE PROTECTION
# ============================================================================

# Require RDS encryption
resource "aws_organizations_policy" "require_rds_encryption" {
  count = var.require_rds_encryption ? 1 : 0
  
  name        = "RequireRDSEncryption"
  description = "Requires encryption for RDS instances and clusters"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyUnencryptedRDS"
        Effect = "Deny"
        Action = [
          "rds:CreateDBInstance",
          "rds:CreateDBCluster"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "rds:StorageEncrypted" = "false"
          }
        }
      }
    ]
  })
  
  tags = var.tags
}

# Prevent RDS public access
resource "aws_organizations_policy" "deny_rds_public_access" {
  count = var.deny_rds_public_access ? 1 : 0
  
  name        = "DenyRDSPublicAccess"
  description = "Prevents RDS instances from being publicly accessible"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyPublicRDS"
        Effect = "Deny"
        Action = [
          "rds:CreateDBInstance",
          "rds:ModifyDBInstance"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "rds:PubliclyAccessible" = "true"
          }
        }
      }
    ]
  })
  
  tags = var.tags
}

# ============================================================================
# NETWORK SECURITY
# ============================================================================

# Restrict VPC changes
resource "aws_organizations_policy" "protect_vpc" {
  count = var.protect_vpc_resources ? 1 : 0
  
  name        = "ProtectVPCResources"
  description = "Protects VPC resources from unauthorized changes"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyVPCChanges"
        Effect = "Deny"
        Action = [
          "ec2:DeleteVpc",
          "ec2:DeleteSubnet",
          "ec2:DeleteInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:DeleteNatGateway",
          "ec2:DeleteRouteTable",
          "ec2:DeleteRoute"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = var.vpc_admin_roles
          }
        }
      }
    ]
  })
  
  tags = var.tags
}

# Deny creation of internet gateways (for isolated accounts)
resource "aws_organizations_policy" "deny_internet_gateway" {
  count = var.deny_internet_gateway ? 1 : 0
  
  name        = "DenyInternetGateway"
  description = "Prevents creation of internet gateways"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyIGW"
        Effect = "Deny"
        Action = [
          "ec2:CreateInternetGateway",
          "ec2:AttachInternetGateway"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = var.tags
}

# Require VPC Flow Logs
resource "aws_organizations_policy" "require_vpc_flow_logs" {
  count = var.require_vpc_flow_logs ? 1 : 0
  
  name        = "RequireVPCFlowLogs"
  description = "Prevents disabling VPC Flow Logs"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyFlowLogDeletion"
        Effect = "Deny"
        Action = [
          "ec2:DeleteFlowLogs"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = var.tags
}

# ============================================================================
# IAM AND SECURITY SERVICES
# ============================================================================

# Prevent disabling Security Hub
resource "aws_organizations_policy" "protect_security_hub" {
  count = var.protect_security_hub ? 1 : 0
  
  name        = "ProtectSecurityHub"
  description = "Prevents disabling or removing Security Hub"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenySecurityHubChanges"
        Effect = "Deny"
        Action = [
          "securityhub:DisableSecurityHub",
          "securityhub:DeleteMembers",
          "securityhub:DisassociateMembers"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = var.tags
}

# Prevent disabling GuardDuty
resource "aws_organizations_policy" "protect_guardduty" {
  count = var.protect_guardduty ? 1 : 0
  
  name        = "ProtectGuardDuty"
  description = "Prevents disabling or removing GuardDuty"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyGuardDutyChanges"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DeleteMembers",
          "guardduty:DisassociateMembers",
          "guardduty:StopMonitoringMembers"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = var.tags
}

# Deny IAM user creation (enforce SSO)
resource "aws_organizations_policy" "deny_iam_users" {
  count = var.enforce_sso_only ? 1 : 0
  
  name        = "DenyIAMUserCreation"
  description = "Prevents creation of IAM users to enforce SSO"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyIAMUsers"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:CreateAccessKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = var.tags
}

# ============================================================================
# COST MANAGEMENT
# ============================================================================

# Restrict expensive instance types
resource "aws_organizations_policy" "deny_expensive_instances" {
  count = var.restrict_expensive_resources ? 1 : 0
  
  name        = "DenyExpensiveInstances"
  description = "Prevents launching expensive EC2 instance types"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyExpensiveInstanceTypes"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "ec2:StartInstances"
        ]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringLike = {
            "ec2:InstanceType" = [
              "*.metal",
              "*.32xlarge",
              "*.24xlarge",
              "*.16xlarge",
              "p*.*",
              "g*.*"
            ]
          }
        }
      }
    ]
  })
  
  tags = var.tags
}

# Prevent Reserved Instance modifications
resource "aws_organizations_policy" "protect_reserved_instances" {
  count = var.protect_reserved_instances ? 1 : 0
  
  name        = "ProtectReservedInstances"
  description = "Prevents modification or deletion of Reserved Instances"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyRIChanges"
        Effect = "Deny"
        Action = [
          "ec2:ModifyReservedInstances",
          "ec2:CancelReservedInstancesListing",
          "rds:DeleteDBInstance",
          "elasticache:DeleteCacheCluster"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = var.billing_admin_roles
          }
        }
      }
    ]
  })
  
  tags = var.tags
}

# ============================================================================
# POLICY ATTACHMENTS
# ============================================================================

# Attach policies to specified OUs
resource "aws_organizations_policy_attachment" "attachments" {
  for_each = var.policy_attachments
  
  policy_id = lookup(local.policy_map, each.value.policy_name, null)
  target_id = each.value.target_ou_id
  
  depends_on = [
    aws_organizations_policy.restrict_instance_types,
    aws_organizations_policy.require_imdsv2,
    aws_organizations_policy.require_ebs_encryption,
    aws_organizations_policy.deny_s3_deletion,
    aws_organizations_policy.require_s3_versioning,
    aws_organizations_policy.require_rds_encryption,
    aws_organizations_policy.deny_rds_public_access,
    aws_organizations_policy.protect_vpc,
    aws_organizations_policy.deny_internet_gateway,
    aws_organizations_policy.require_vpc_flow_logs,
    aws_organizations_policy.protect_security_hub,
    aws_organizations_policy.protect_guardduty,
    aws_organizations_policy.deny_iam_users,
    aws_organizations_policy.deny_expensive_instances,
    aws_organizations_policy.protect_reserved_instances
  ]
}

# Local map for policy lookups
locals {
  policy_map = merge(
    var.enable_instance_type_restrictions ? { "RestrictEC2InstanceTypes" = aws_organizations_policy.restrict_instance_types[0].id } : {},
    var.require_imdsv2 ? { "RequireIMDSv2" = aws_organizations_policy.require_imdsv2[0].id } : {},
    var.require_ebs_encryption ? { "RequireEBSEncryption" = aws_organizations_policy.require_ebs_encryption[0].id } : {},
    var.protect_s3_buckets ? { "DenyS3BucketDeletion" = aws_organizations_policy.deny_s3_deletion[0].id } : {},
    var.require_s3_versioning ? { "RequireS3Versioning" = aws_organizations_policy.require_s3_versioning[0].id } : {},
    var.require_rds_encryption ? { "RequireRDSEncryption" = aws_organizations_policy.require_rds_encryption[0].id } : {},
    var.deny_rds_public_access ? { "DenyRDSPublicAccess" = aws_organizations_policy.deny_rds_public_access[0].id } : {},
    var.protect_vpc_resources ? { "ProtectVPCResources" = aws_organizations_policy.protect_vpc[0].id } : {},
    var.deny_internet_gateway ? { "DenyInternetGateway" = aws_organizations_policy.deny_internet_gateway[0].id } : {},
    var.require_vpc_flow_logs ? { "RequireVPCFlowLogs" = aws_organizations_policy.require_vpc_flow_logs[0].id } : {},
    var.protect_security_hub ? { "ProtectSecurityHub" = aws_organizations_policy.protect_security_hub[0].id } : {},
    var.protect_guardduty ? { "ProtectGuardDuty" = aws_organizations_policy.protect_guardduty[0].id } : {},
    var.enforce_sso_only ? { "DenyIAMUserCreation" = aws_organizations_policy.deny_iam_users[0].id } : {},
    var.restrict_expensive_resources ? { "DenyExpensiveInstances" = aws_organizations_policy.deny_expensive_instances[0].id } : {},
    var.protect_reserved_instances ? { "ProtectReservedInstances" = aws_organizations_policy.protect_reserved_instances[0].id } : {}
  )
}
