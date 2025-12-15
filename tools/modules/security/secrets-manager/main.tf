# modules/security/secrets-manager/main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

locals {
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "security/secrets-manager"
  })
}

# Generate random password if needed
resource "random_password" "secret" {
  count = var.generate_secret_string ? 1 : 0
  
  length  = var.password_length
  special = var.password_include_special
  
  lifecycle {
    ignore_changes = [length, special]
  }
}

# Secrets Manager Secret
resource "aws_secretsmanager_secret" "main" {
  name        = var.secret_name
  description = var.description
  
  kms_key_id = var.kms_key_id
  
  recovery_window_in_days = var.recovery_window_in_days
  
  tags = merge(local.common_tags, {
    Name = var.secret_name
    Type = "secret"
  })
}

# Secret Version
resource "aws_secretsmanager_secret_version" "main" {
  count = var.secret_string != null || var.generate_secret_string ? 1 : 0
  
  secret_id = aws_secretsmanager_secret.main.id
  
  secret_string = var.generate_secret_string ? jsonencode({
    username = var.username
    password = random_password.secret[0].result
  }) : var.secret_string
  
  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Resource Policy
resource "aws_secretsmanager_secret_policy" "main" {
  count = var.resource_policy != null ? 1 : 0
  
  secret_arn = aws_secretsmanager_secret.main.arn
  policy     = var.resource_policy
}

# Rotation Configuration
resource "aws_secretsmanager_secret_rotation" "main" {
  count = var.enable_rotation ? 1 : 0
  
  secret_id           = aws_secretsmanager_secret.main.id
  rotation_lambda_arn = var.rotation_lambda_arn
  
  rotation_rules {
    automatically_after_days = var.rotation_days
  }
}

# Lambda function for rotation (if create_rotation_lambda is true)
resource "aws_lambda_function" "rotation" {
  count = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  
  filename      = var.rotation_lambda_zip_file
  function_name = "${var.secret_name}-rotation"
  role          = aws_iam_role.rotation_lambda[0].arn
  handler       = var.rotation_lambda_handler
  runtime       = var.rotation_lambda_runtime
  timeout       = var.rotation_lambda_timeout
  
  environment {
    variables = var.rotation_lambda_environment_variables
  }
  
  vpc_config {
    subnet_ids         = var.rotation_lambda_subnet_ids
    security_group_ids = var.rotation_lambda_security_group_ids
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.secret_name}-rotation"
    Type = "rotation-lambda"
  })
}

# IAM Role for Rotation Lambda
resource "aws_iam_role" "rotation_lambda" {
  count = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  
  name = "${var.secret_name}-rotation-lambda-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach Lambda execution policy
resource "aws_iam_role_policy_attachment" "rotation_lambda_execution" {
  count = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  
  role       = aws_iam_role.rotation_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Custom policy for Secrets Manager access
resource "aws_iam_role_policy" "rotation_lambda_secrets" {
  count = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  
  name = "${var.secret_name}-rotation-secrets-policy"
  role = aws_iam_role.rotation_lambda[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetRandomPassword"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda permission for Secrets Manager
resource "aws_lambda_permission" "secrets_manager" {
  count = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  
  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation[0].function_name
  principal     = "secretsmanager.amazonaws.com"
}

# CloudWatch Log Group for rotation Lambda
resource "aws_cloudwatch_log_group" "rotation_lambda" {
  count = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  
  name              = "/aws/lambda/${aws_lambda_function.rotation[0].function_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${var.secret_name}-rotation-logs"
    Type = "log-group"
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "rotation_failed" {
  count = var.enable_rotation && var.create_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.secret_name}-rotation-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RotationFailed"
  namespace           = "AWS/SecretsManager"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Alert when secret rotation fails"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    SecretId = aws_secretsmanager_secret.main.id
  }
  
  tags = local.common_tags
}

# modules/security/secrets-manager/variables.tf
variable "secret_name" {
  description = "Name of the secret"
  type        = string
}

variable "description" {
  description = "Description of the secret"
  type        = string
  default     = ""
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "Number of days to retain secret before permanent deletion"
  type        = number
  default     = 30
  
  validation {
    condition     = var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30
    error_message = "Recovery window must be between 7 and 30 days."
  }
}

# Secret Value
variable "secret_string" {
  description = "Secret string (JSON format)"
  type        = string
  default     = null
  sensitive   = true
}

variable "generate_secret_string" {
  description = "Generate a random password for the secret"
  type        = bool
  default     = false
}

variable "username" {
  description = "Username for generated secret (if generate_secret_string is true)"
  type        = string
  default     = "admin"
}

variable "password_length" {
  description = "Length of generated password"
  type        = number
  default     = 32
}

variable "password_include_special" {
  description = "Include special characters in generated password"
  type        = bool
  default     = true
}

# Resource Policy
variable "resource_policy" {
  description = "Resource-based policy for the secret"
  type        = string
  default     = null
}

# Rotation
variable "enable_rotation" {
  description = "Enable automatic rotation"
  type        = bool
  default     = false
}

variable "rotation_lambda_arn" {
  description = "ARN of Lambda function for rotation"
  type        = string
  default     = null
}

variable "rotation_days" {
  description = "Number of days between automatic rotations"
  type        = number
  default     = 30
}

variable "create_rotation_lambda" {
  description = "Create Lambda function for rotation"
  type        = bool
  default     = false
}

variable "rotation_lambda_zip_file" {
  description = "Path to Lambda function zip file"
  type        = string
  default     = null
}

variable "rotation_lambda_handler" {
  description = "Lambda function handler"
  type        = string
  default     = "lambda_function.lambda_handler"
}

variable "rotation_lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.11"
}

variable "rotation_lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "rotation_lambda_environment_variables" {
  description = "Environment variables for rotation Lambda"
  type        = map(string)
  default     = {}
}

variable "rotation_lambda_subnet_ids" {
  description = "Subnet IDs for rotation Lambda VPC config"
  type        = list(string)
  default     = []
}

variable "rotation_lambda_security_group_ids" {
  description = "Security group IDs for rotation Lambda VPC config"
  type        = list(string)
  default     = []
}

# Monitoring
variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms"
  type        = bool
  default     = false
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarm triggers"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# modules/security/secrets-manager/outputs.tf
output "secret_arn" {
  description = "ARN of the secret"
  value       = aws_secretsmanager_secret.main.arn
}

output "secret_id" {
  description = "ID of the secret"
  value       = aws_secretsmanager_secret.main.id
}

output "secret_name" {
  description = "Name of the secret"
  value       = aws_secretsmanager_secret.main.name
}

output "secret_version_id" {
  description = "Version ID of the secret"
  value       = var.secret_string != null || var.generate_secret_string ? aws_secretsmanager_secret_version.main[0].version_id : null
}

output "rotation_lambda_arn" {
  description = "ARN of the rotation Lambda function"
  value       = var.enable_rotation && var.create_rotation_lambda ? aws_lambda_function.rotation[0].arn : null
}

output "rotation_enabled" {
  description = "Whether rotation is enabled"
  value       = var.enable_rotation
}
