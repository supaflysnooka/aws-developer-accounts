# modules/compute/ec2/main.tf
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
    Module    = "compute/ec2"
  })
}

# Get latest AMI
data "aws_ami" "amazon_linux_2023" {
  count = var.ami_id == null && var.ami_filter_name != null ? 1 : 0
  
  most_recent = true
  owners      = [var.ami_owner]
  
  filter {
    name   = "name"
    values = [var.ami_filter_name]
  }
  
  filter {
    name   = "architecture"
    values = [var.architecture]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 Instance
resource "aws_instance" "main" {
  count = var.instance_count
  
  ami           = var.ami_id != null ? var.ami_id : data.aws_ami.amazon_linux_2023[0].id
  instance_type = var.instance_type
  
  # Network Configuration
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = var.security_group_ids
  associate_public_ip_address = var.associate_public_ip_address
  
  # IAM
  iam_instance_profile = var.iam_instance_profile_name != null ? var.iam_instance_profile_name : (var.create_iam_instance_profile ? aws_iam_instance_profile.main[0].name : null)
  
  # Storage
  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = var.root_volume_delete_on_termination
    encrypted             = var.root_volume_encrypted
    kms_key_id           = var.kms_key_id
  }
  
  # Additional EBS Volumes
  dynamic "ebs_block_device" {
    for_each = var.ebs_volumes
    content {
      device_name           = ebs_block_device.value.device_name
      volume_type           = ebs_block_device.value.volume_type
      volume_size           = ebs_block_device.value.volume_size
      iops                  = ebs_block_device.value.iops
      throughput            = ebs_block_device.value.throughput
      delete_on_termination = ebs_block_device.value.delete_on_termination
      encrypted             = ebs_block_device.value.encrypted
      kms_key_id           = ebs_block_device.value.kms_key_id
    }
  }
  
  # Key Pair
  key_name = var.key_name
  
  # User Data
  user_data                   = var.user_data
  user_data_replace_on_change = var.user_data_replace_on_change
  
  # Monitoring
  monitoring = var.enable_detailed_monitoring
  
  # Metadata Options
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.require_imdsv2 ? "required" : "optional"
    http_put_response_hop_limit = var.metadata_hop_limit
  }
  
  # Lifecycle
  disable_api_termination = var.enable_termination_protection
  
  tags = merge(local.common_tags, {
    Name = var.instance_count > 1 ? "${var.instance_name}-${count.index + 1}" : var.instance_name
    Type = "ec2-instance"
  })
  
  volume_tags = merge(local.common_tags, {
    Name = var.instance_count > 1 ? "${var.instance_name}-${count.index + 1}" : var.instance_name
    Type = "ebs-volume"
  })
}

# Elastic IP
resource "aws_eip" "main" {
  count = var.create_eip ? var.instance_count : 0
  
  domain   = "vpc"
  instance = aws_instance.main[count.index].id
  
  tags = merge(local.common_tags, {
    Name = var.instance_count > 1 ? "${var.instance_name}-eip-${count.index + 1}" : "${var.instance_name}-eip"
    Type = "elastic-ip"
  })
  
  depends_on = [aws_instance.main]
}

# IAM Role for EC2
resource "aws_iam_role" "main" {
  count = var.create_iam_instance_profile ? 1 : 0
  
  name = "${var.instance_name}-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach managed policies
resource "aws_iam_role_policy_attachment" "managed_policies" {
  for_each = var.create_iam_instance_profile ? toset(var.iam_managed_policy_arns) : []
  
  role       = aws_iam_role.main[0].name
  policy_arn = each.value
}

# Custom inline policies
resource "aws_iam_role_policy" "inline_policies" {
  for_each = var.create_iam_instance_profile ? var.iam_inline_policies : {}
  
  name   = each.key
  role   = aws_iam_role.main[0].id
  policy = each.value
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "main" {
  count = var.create_iam_instance_profile ? 1 : 0
  
  name = "${var.instance_name}-profile"
  role = aws_iam_role.main[0].name
  
  tags = local.common_tags
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "instance_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/ec2/${var.instance_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${var.instance_name}-logs"
    Type = "log-group"
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.create_cloudwatch_alarms ? var.instance_count : 0
  
  alarm_name          = "${var.instance_name}-${count.index + 1}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors EC2 CPU utilization"
  alarm_actions       = var.alarm_actions
  
  dimensions = {
    InstanceId = aws_instance.main[count.index].id
  }
  
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  count = var.create_cloudwatch_alarms ? var.instance_count : 0
  
  alarm_name          = "${var.instance_name}-${count.index + 1}-status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "This metric monitors EC2 status checks"
  alarm_actions       = var.alarm_actions
  
  dimensions = {
    InstanceId = aws_instance.main[count.index].id
  }
  
  tags = local.common_tags
}

# modules/compute/ec2/variables.tf
variable "instance_name" {
  description = "Name of the EC2 instance"
  type        = string
}

variable "instance_count" {
  description = "Number of instances to create"
  type        = number
  default     = 1
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition     = can(regex("^(t3|t4g|t3a)\\.(nano|micro|small|medium)$", var.instance_type))
    error_message = "Instance type must be cost-optimized (t3/t4g nano, micro, small, or medium)."
  }
}

variable "ami_id" {
  description = "AMI ID to use for the instance"
  type        = string
  default     = null
}

variable "ami_filter_name" {
  description = "AMI filter name pattern"
  type        = string
  default     = "al2023-ami-*-x86_64"
}

variable "ami_owner" {
  description = "AMI owner account ID"
  type        = string
  default     = "amazon"
}

variable "architecture" {
  description = "CPU architecture"
  type        = string
  default     = "x86_64"
}

# Network
variable "subnet_ids" {
  description = "List of subnet IDs for instance placement"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "associate_public_ip_address" {
  description = "Associate a public IP address"
  type        = bool
  default     = false
}

variable "create_eip" {
  description = "Create and associate Elastic IP"
  type        = bool
  default     = false
}

# Storage
variable "root_volume_type" {
  description = "Root volume type"
  type        = string
  default     = "gp3"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 20
}

variable "root_volume_delete_on_termination" {
  description = "Delete root volume on termination"
  type        = bool
  default     = true
}

variable "root_volume_encrypted" {
  description = "Encrypt root volume"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
  default     = null
}

variable "ebs_volumes" {
  description = "Additional EBS volumes to attach"
  type = list(object({
    device_name           = string
    volume_type           = string
    volume_size           = number
    iops                  = optional(number)
    throughput            = optional(number)
    delete_on_termination = optional(bool, true)
    encrypted             = optional(bool, true)
    kms_key_id           = optional(string)
  }))
  default = []
}

# Access
variable "key_name" {
  description = "SSH key pair name"
  type        = string
  default     = null
}

variable "user_data" {
  description = "User data script"
  type        = string
  default     = null
}

variable "user_data_replace_on_change" {
  description = "Replace instance when user data changes"
  type        = bool
  default     = false
}

# IAM
variable "create_iam_instance_profile" {
  description = "Create IAM instance profile"
  type        = bool
  default     = false
}

variable "iam_instance_profile_name" {
  description = "Existing IAM instance profile name"
  type        = string
  default     = null
}

variable "iam_managed_policy_arns" {
  description = "List of IAM managed policy ARNs to attach"
  type        = list(string)
  default     = []
}

variable "iam_inline_policies" {
  description = "Map of inline policies to attach"
  type        = map(string)
  default     = {}
}

# Monitoring
variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 30
}

# Metadata
variable "require_imdsv2" {
  description = "Require IMDSv2 for instance metadata"
  type        = bool
  default     = true
}

variable "metadata_hop_limit" {
  description = "Metadata service hop limit"
  type        = number
  default     = 1
}

# Protection
variable "enable_termination_protection" {
  description = "Enable termination protection"
  type        = bool
  default     = false
}

# CloudWatch Alarms
variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms"
  type        = bool
  default     = false
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for alarm"
  type        = number
  default     = 80
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

# modules/compute/ec2/outputs.tf
output "instance_ids" {
  description = "List of instance IDs"
  value       = aws_instance.main[*].id
}

output "instance_arns" {
  description = "List of instance ARNs"
  value       = aws_instance.main[*].arn
}

output "private_ips" {
  description = "List of private IP addresses"
  value       = aws_instance.main[*].private_ip
}

output "public_ips" {
  description = "List of public IP addresses"
  value       = aws_instance.main[*].public_ip
}

output "elastic_ips" {
  description = "List of Elastic IPs"
  value       = var.create_eip ? aws_eip.main[*].public_ip : []
}

output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = var.create_iam_instance_profile ? aws_iam_role.main[0].arn : null
}

output "instance_profile_arn" {
  description = "ARN of the instance profile"
  value       = var.create_iam_instance_profile ? aws_iam_instance_profile.main[0].arn : null
}
