# modules/account-factory/cis-compliance.tf
# CIS AWS Foundations Benchmark Compliance Resources
# Add this file to your existing account-factory module

# ============================================================================
# CIS Config.1 (CRITICAL) - AWS Config should be enabled
# ============================================================================

resource "aws_config_configuration_recorder" "cis" {
  name     = "cis-config-recorder"
  role_arn = aws_iam_service_linked_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "cis" {
  name           = "cis-config-delivery"
  s3_bucket_name = aws_s3_bucket.config.bucket

  depends_on = [aws_config_configuration_recorder.cis]
}

resource "aws_config_configuration_recorder_status" "cis" {
  name       = aws_config_configuration_recorder.cis.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.cis]
}

# Service-linked role for AWS Config
resource "aws_iam_service_linked_role" "config" {
  aws_service_name = "config.amazonaws.com"
  description      = "Service-linked role for AWS Config (CIS Config.1)"
}

# S3 bucket for Config
resource "aws_s3_bucket" "config" {
  bucket = "config-bucket-${var.developer_name}-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    var.tags,
    {
      Name       = "AWS Config Bucket"
      Purpose    = "CIS Compliance - Config.1"
      CISControl = "Config.1"
    }
  )
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketPutObject"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ============================================================================
# CIS EC2.2 (HIGH) - VPC default security group should not allow traffic
# ============================================================================

resource "aws_default_security_group" "default" {
  vpc_id = var.vpc_id

  # No ingress or egress rules = deny all traffic
  
  tags = merge(
    var.tags,
    {
      Name       = "Default SG - CIS Restricted"
      CISControl = "EC2.2"
      Note       = "CIS compliance - no traffic allowed"
    }
  )
}

# ============================================================================
# CIS EC2.6 (MEDIUM) - VPC flow logging should be enabled
# ============================================================================

resource "aws_flow_log" "vpc" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name       = "VPC Flow Logs"
      CISControl = "EC2.6"
    }
  )
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/flowlogs/${var.vpc_id}"
  retention_in_days = 90

  tags = merge(
    var.tags,
    {
      Name       = "VPC Flow Logs"
      CISControl = "EC2.6"
    }
  )
}

resource "aws_iam_role" "flow_logs" {
  name = "VPCFlowLogsRole-${var.developer_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name       = "VPC Flow Logs Role"
      CISControl = "EC2.6"
    }
  )
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "vpc-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# CIS IAM.11-17 (MEDIUM/LOW) - IAM Password Policy
# ============================================================================

resource "aws_iam_account_password_policy" "cis" {
  minimum_password_length        = 14     # CIS IAM.15
  require_uppercase_characters   = true   # CIS IAM.11
  require_lowercase_characters   = true   # CIS IAM.12
  require_symbols                = true   # CIS IAM.13
  require_numbers                = true   # CIS IAM.14
  password_reuse_prevention      = 24     # CIS IAM.16 - prevent reuse of last 24 passwords
  max_password_age               = 90     # CIS IAM.17 - expire after 90 days
  allow_users_to_change_password = true
}

# ============================================================================
# CIS IAM.18 (LOW) - Support role for AWS Support incidents
# ============================================================================

resource "aws_iam_role" "support" {
  name        = "AWSSupportRole"
  description = "Role for managing AWS Support incidents (CIS IAM.18)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.management_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "BoseSupport"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name       = "AWS Support Role"
      CISControl = "IAM.18"
    }
  )
}

resource "aws_iam_role_policy_attachment" "support" {
  role       = aws_iam_role.support.name
  policy_arn = "arn:aws:iam::aws:policy/AWSSupportAccess"
}

# ============================================================================
# Data sources
# ============================================================================

data "aws_caller_identity" "current" {}
