variable "region" {
  description = "AWS region for the provider"
  type        = string
  default     = "us-east-2"
}

variable "feature_set" {
  description = "Feature set for the organization (ALL or CONSOLIDATED_BILLING)"
  type        = string
  default     = "ALL"
  
  validation {
    condition     = contains(["ALL", "CONSOLIDATED_BILLING"], var.feature_set)
    error_message = "Feature set must be either ALL or CONSOLIDATED_BILLING."
  }
}

variable "enabled_policy_types" {
  description = "List of policy types to enable in the organization"
  type        = list(string)
  default = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
    "BACKUP_POLICY"
  ]
}

variable "aws_service_access_principals" {
  description = "List of AWS service principals to enable for organization access"
  type        = list(string)
  default = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "ram.amazonaws.com",
    "ssm.amazonaws.com",
    "sso.amazonaws.com",
    "tagpolicies.tag.amazonaws.com",
    "backup.amazonaws.com",
    "member.org.stacksets.cloudformation.amazonaws.com"
  ]
}

variable "restrict_regions" {
  description = "Whether to restrict operations to approved regions"
  type        = bool
  default     = false
}

variable "approved_regions" {
  description = "List of approved AWS regions (only used if restrict_regions is true)"
  type        = list(string)
  default = [
    "us-east-1",
    "us-east-2"
  ]
}

variable "enable_aws_config" {
  description = "Whether to enforce AWS Config across the organization"
  type        = bool
  default     = true
}

variable "protect_cloudtrail" {
  description = "Whether to protect CloudTrail from being disabled or deleted"
  type        = bool
  default     = true
}
