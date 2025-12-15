# modules/storage/s3/main.tf
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
    Module    = "storage/s3"
  })
}

# S3 Bucket
resource "aws_s3_bucket" "main" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  
  tags = merge(local.common_tags, {
    Name = var.bucket_name
    Type = "s3-bucket"
  })
}

# Bucket Versioning
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  
  versioning_configuration {
    status     = var.enable_versioning ? "Enabled" : "Disabled"
    mfa_delete = var.enable_mfa_delete ? "Enabled" : "Disabled"
  }
}

# Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.kms_master_key_id
    }
    bucket_key_enabled = var.bucket_key_enabled
  }
}

# Public Access Block
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id
  
  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}

# Bucket Policy
resource "aws_s3_bucket_policy" "main" {
  count = var.bucket_policy != null ? 1 : 0
  
  bucket = aws_s3_bucket.main.id
  policy = var.bucket_policy
  
  depends_on = [aws_s3_bucket_public_access_block.main]
}

# Lifecycle Rules
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0
  
  bucket = aws_s3_bucket.main.id
  
  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"
      
      # Filter
      dynamic "filter" {
        for_each = rule.value.filter != null ? [rule.value.filter] : []
        content {
          prefix = filter.value.prefix
          
          dynamic "tag" {
            for_each = filter.value.tags != null ? filter.value.tags : {}
            content {
              key   = tag.key
              value = tag.value
            }
          }
        }
      }
      
      # Transition to IA
      dynamic "transition" {
        for_each = rule.value.transition_to_ia_days != null ? [1] : []
        content {
          days          = rule.value.transition_to_ia_days
          storage_class = "STANDARD_IA"
        }
      }
      
      # Transition to Glacier
      dynamic "transition" {
        for_each = rule.value.transition_to_glacier_days != null ? [1] : []
        content {
          days          = rule.value.transition_to_glacier_days
          storage_class = "GLACIER"
        }
      }
      
      # Transition to Deep Archive
      dynamic "transition" {
        for_each = rule.value.transition_to_deep_archive_days != null ? [1] : []
        content {
          days          = rule.value.transition_to_deep_archive_days
          storage_class = "DEEP_ARCHIVE"
        }
      }
      
      # Expiration
      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }
      
      # Noncurrent version transitions
      dynamic "noncurrent_version_transition" {
        for_each = rule.value.noncurrent_version_transition_to_ia_days != null ? [1] : []
        content {
          noncurrent_days = rule.value.noncurrent_version_transition_to_ia_days
          storage_class   = "STANDARD_IA"
        }
      }
      
      # Noncurrent version expiration
      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days != null ? [1] : []
        content {
          noncurrent_days = rule.value.noncurrent_version_expiration_days
        }
      }
      
      # Abort incomplete multipart uploads
      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload_days != null ? [1] : []
        content {
          days_after_initiation = rule.value.abort_incomplete_multipart_upload_days
        }
      }
    }
  }
  
  depends_on = [aws_s3_bucket_versioning.main]
}

# CORS Configuration
resource "aws_s3_bucket_cors_configuration" "main" {
  count = length(var.cors_rules) > 0 ? 1 : 0
  
  bucket = aws_s3_bucket.main.id
  
  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

# Logging
resource "aws_s3_bucket_logging" "main" {
  count = var.enable_logging ? 1 : 0
  
  bucket = aws_s3_bucket.main.id
  
  target_bucket = var.logging_target_bucket
  target_prefix = var.logging_target_prefix != null ? var.logging_target_prefix : "${var.bucket_name}/"
}

# Replication Configuration
resource "aws_s3_bucket_replication_configuration" "main" {
  count = var.enable_replication ? 1 : 0
  
  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.main.id
  
  dynamic "rule" {
    for_each = var.replication_rules
    content {
      id       = rule.value.id
      priority = rule.value.priority
      status   = rule.value.enabled ? "Enabled" : "Disabled"
      
      filter {
        prefix = rule.value.prefix
      }
      
      destination {
        bucket        = rule.value.destination_bucket_arn
        storage_class = rule.value.storage_class
        
        dynamic "replication_time" {
          for_each = rule.value.enable_replication_time_control ? [1] : []
          content {
            status = "Enabled"
            time {
              minutes = 15
            }
          }
        }
        
        dynamic "metrics" {
          for_each = rule.value.enable_replication_metrics ? [1] : []
          content {
            status = "Enabled"
            event_threshold {
              minutes = 15
            }
          }
        }
      }
      
      dynamic "delete_marker_replication" {
        for_each = rule.value.replicate_delete_markers ? [1] : []
        content {
          status = "Enabled"
        }
      }
    }
  }
  
  depends_on = [aws_s3_bucket_versioning.main]
}

# IAM Role for Replication
resource "aws_iam_role" "replication" {
  count = var.enable_replication ? 1 : 0
  
  name = "${var.bucket_name}-replication-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy" "replication" {
  count = var.enable_replication ? 1 : 0
  
  name = "${var.bucket_name}-replication-policy"
  role = aws_iam_role.replication[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.main.arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.main.arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect = "Allow"
        Resource = [
          for rule in var.replication_rules :
          "${rule.destination_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Object Lock Configuration
resource "aws_s3_bucket_object_lock_configuration" "main" {
  count = var.enable_object_lock ? 1 : 0
  
  bucket = aws_s3_bucket.main.id
  
  rule {
    default_retention {
      mode  = var.object_lock_mode
      days  = var.object_lock_days
      years = var.object_lock_years
    }
  }
}

# Notification Configuration
resource "aws_s3_bucket_notification" "main" {
  count = var.enable_notifications ? 1 : 0
  
  bucket = aws_s3_bucket.main.id
  
  # Lambda notifications
  dynamic "lambda_function" {
    for_each = var.lambda_notifications
    content {
      lambda_function_arn = lambda_function.value.lambda_arn
      events              = lambda_function.value.events
      filter_prefix       = lambda_function.value.filter_prefix
      filter_suffix       = lambda_function.value.filter_suffix
    }
  }
  
  # SNS notifications
  dynamic "topic" {
    for_each = var.sns_notifications
    content {
      topic_arn     = topic.value.topic_arn
      events        = topic.value.events
      filter_prefix = topic.value.filter_prefix
      filter_suffix = topic.value.filter_suffix
    }
  }
  
  # SQS notifications
  dynamic "queue" {
    for_each = var.sqs_notifications
    content {
      queue_arn     = queue.value.queue_arn
      events        = queue.value.events
      filter_prefix = queue.value.filter_prefix
      filter_suffix = queue.value.filter_suffix
    }
  }
  
  depends_on = [aws_s3_bucket_public_access_block.main]
}

# Intelligent Tiering Configuration
resource "aws_s3_bucket_intelligent_tiering_configuration" "main" {
  count = var.enable_intelligent_tiering ? 1 : 0
  
  bucket = aws_s3_bucket.main.id
  name   = "EntireBucket"
  
  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_deep_archive_days
  }
  
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_archive_days
  }
}

# Inventory Configuration
resource "aws_s3_bucket_inventory" "main" {
  count = var.enable_inventory ? 1 : 0
  
  bucket = aws_s3_bucket.main.id
  name   = "${var.bucket_name}-inventory"
  
  included_object_versions = "All"
  
  schedule {
    frequency = var.inventory_frequency
  }
  
  destination {
    bucket {
      format     = "CSV"
      bucket_arn = var.inventory_destination_bucket_arn
      prefix     = var.inventory_destination_prefix
    }
  }
  
  optional_fields = [
    "Size",
    "LastModifiedDate",
    "StorageClass",
    "ETag",
    "IsMultipartUploaded",
    "ReplicationStatus",
    "EncryptionStatus"
  ]
}
