# modules/containers/ecr/main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "containers/ecr"
  })
}

# ECR Repository
resource "aws_ecr_repository" "main" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability
  
  # Image Scanning
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
  
  # Encryption
  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.kms_key_arn
  }
  
  tags = merge(local.common_tags, {
    Name = var.repository_name
    Type = "ecr-repository"
  })
}

# Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "main" {
  count = var.enable_lifecycle_policy ? 1 : 0
  
  repository = aws_ecr_repository.main.name
  
  policy = jsonencode({
    rules = concat(
      # Keep last N untagged images
      var.untagged_image_retention_count > 0 ? [{
        rulePriority = 1
        description  = "Keep last ${var.untagged_image_retention_count} untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = var.untagged_image_retention_count
        }
        action = {
          type = "expire"
        }
      }] : [],
      
      # Keep images for N days
      var.image_retention_days > 0 ? [{
        rulePriority = 2
        description  = "Delete images older than ${var.image_retention_days} days"
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.image_retention_days
        }
        action = {
          type = "expire"
        }
      }] : [],
      
      # Keep tagged images
      var.tagged_image_retention_count > 0 ? [{
        rulePriority = 3
        description  = "Keep last ${var.tagged_image_retention_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = var.tag_prefix_list
          countType     = "imageCountMoreThan"
          countNumber   = var.tagged_image_retention_count
        }
        action = {
          type = "expire"
        }
      }] : []
    )
  })
}

# Repository Policy
resource "aws_ecr_repository_policy" "main" {
  count = var.enable_repository_policy ? 1 : 0
  
  repository = aws_ecr_repository.main.name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # Allow pull from specific accounts
      length(var.pull_account_ids) > 0 ? [{
        Sid    = "AllowPullFromAccounts"
        Effect = "Allow"
        Principal = {
          AWS = [for account_id in var.pull_account_ids : "arn:aws:iam::${account_id}:root"]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }] : [],
      
      # Allow push from specific accounts
      length(var.push_account_ids) > 0 ? [{
        Sid    = "AllowPushFromAccounts"
        Effect = "Allow"
        Principal = {
          AWS = [for account_id in var.push_account_ids : "arn:aws:iam::${account_id}:root"]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
      }] : [],
      
      # Custom policy statements
      var.custom_policy_statements
    )
  })
}

# Replication Configuration
resource "aws_ecr_replication_configuration" "main" {
  count = var.enable_replication ? 1 : 0
  
  replication_configuration {
    dynamic "rule" {
      for_each = var.replication_destinations
      content {
        destination {
          region      = rule.value.region
          registry_id = rule.value.registry_id
        }
        
        dynamic "repository_filter" {
          for_each = rule.value.repository_filter != null ? [rule.value.repository_filter] : []
          content {
            filter      = repository_filter.value.filter
            filter_type = repository_filter.value.filter_type
          }
        }
      }
    }
  }
}

# Registry Scanning Configuration
resource "aws_ecr_registry_scanning_configuration" "main" {
  count = var.enable_registry_scanning ? 1 : 0
  
  scan_type = var.scan_type
  
  dynamic "rule" {
    for_each = var.scanning_rules
    content {
      scan_frequency = rule.value.scan_frequency
      
      repository_filter {
        filter      = rule.value.repository_filter
        filter_type = rule.value.filter_type
      }
    }
  }
}

# CloudWatch Log Group for Image Scanning
resource "aws_cloudwatch_log_group" "scan_results" {
  count = var.enable_scan_logging ? 1 : 0
  
  name              = "/aws/ecr/${var.repository_name}/scan-results"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${var.repository_name}-scan-logs"
    Type = "log-group"
  })
}

# EventBridge Rule for Image Scan Findings
resource "aws_cloudwatch_event_rule" "image_scan_findings" {
  count = var.enable_scan_notifications ? 1 : 0
  
  name        = "${var.repository_name}-scan-findings"
  description = "Capture ECR image scan findings"
  
  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Scan"]
    detail = {
      repository-name = [var.repository_name]
      scan-status     = ["COMPLETE"]
      finding-severity-counts = {
        CRITICAL = [{
          exists = true
        }]
      }
    }
  })
  
  tags = local.common_tags
}

# EventBridge Target (SNS)
resource "aws_cloudwatch_event_target" "sns" {
  count = var.enable_scan_notifications && var.sns_topic_arn != null ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.image_scan_findings[0].name
  target_id = "SendToSNS"
  arn       = var.sns_topic_arn
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_severity_vulnerabilities" {
  count = var.create_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.repository_name}-high-severity-vulns"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HighSeverityVulnerabilities"
  namespace           = "AWS/ECR"
  period              = "300"
  statistic           = "Maximum"
  threshold           = var.vulnerability_threshold
  alarm_description   = "Alert on high severity vulnerabilities in ECR images"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    RepositoryName = var.repository_name
  }
  
  tags = local.common_tags
}

# modules/containers/ecr/variables.tf
variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "image_tag_mutability" {
  description = "Image tag mutability setting"
  type        = string
  default     = "MUTABLE"
  
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Image tag mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "Encryption type (AES256 or KMS)"
  type        = string
  default     = "AES256"
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption (if encryption_type is KMS)"
  type        = string
  default     = null
}

# Lifecycle Policy
variable "enable_lifecycle_policy" {
  description = "Enable lifecycle policy"
  type        = bool
  default     = true
}

variable "untagged_image_retention_count" {
  description = "Number of untagged images to keep"
  type        = number
  default     = 3
}

variable "tagged_image_retention_count" {
  description = "Number of tagged images to keep"
  type        = number
  default     = 10
}

variable "image_retention_days" {
  description = "Days to retain images (0 to disable)"
  type        = number
  default     = 0
}

variable "tag_prefix_list" {
  description = "List of tag prefixes to apply retention policy"
  type        = list(string)
  default     = ["v", "prod"]
}

# Repository Policy
variable "enable_repository_policy" {
  description = "Enable repository policy"
  type        = bool
  default     = false
}

variable "pull_account_ids" {
  description = "AWS account IDs allowed to pull images"
  type        = list(string)
  default     = []
}

variable "push_account_ids" {
  description = "AWS account IDs allowed to push images"
  type        = list(string)
  default     = []
}

variable "custom_policy_statements" {
  description = "Custom policy statements"
  type        = list(any)
  default     = []
}

# Replication
variable "enable_replication" {
  description = "Enable cross-region replication"
  type        = bool
  default     = false
}

variable "replication_destinations" {
  description = "Replication destinations"
  type = list(object({
    region      = string
    registry_id = string
    repository_filter = optional(object({
      filter      = string
      filter_type = string
    }))
  }))
  default = []
}

# Scanning
variable "enable_registry_scanning" {
  description = "Enable registry-level scanning configuration"
  type        = bool
  default     = false
}

variable "scan_type" {
  description = "Scan type (BASIC or ENHANCED)"
  type        = string
  default     = "BASIC"
}

variable "scanning_rules" {
  description = "Scanning rules"
  type = list(object({
    scan_frequency    = string
    repository_filter = string
    filter_type       = string
  }))
  default = []
}

variable "enable_scan_logging" {
  description = "Enable scan result logging"
  type        = bool
  default     = false
}

variable "enable_scan_notifications" {
  description = "Enable scan result notifications"
  type        = bool
  default     = false
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for scan notifications"
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 30
}

# CloudWatch Alarms
variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms"
  type        = bool
  default     = false
}

variable "vulnerability_threshold" {
  description = "Threshold for high severity vulnerabilities alarm"
  type        = number
  default     = 0
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarm triggers"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# modules/containers/ecr/outputs.tf
output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.main.arn
}

output "repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.main.repository_url
}

output "repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.main.name
}

output "registry_id" {
  description = "Registry ID where the repository was created"
  value       = aws_ecr_repository.main.registry_id
}
