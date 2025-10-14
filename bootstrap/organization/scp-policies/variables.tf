variable "region" {
  description = "AWS region for the provider"
  type        = string
  default     = "us-east-2"
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Module    = "scp-policies"
  }
}

# ============================================================================
# COMPUTE RESTRICTIONS
# ============================================================================

variable "enable_instance_type_restrictions" {
  description = "Enable restrictions on EC2 instance types"
  type        = bool
  default     = false
}

variable "allowed_instance_types" {
  description = "List of allowed EC2 instance type patterns (e.g., 't3.*', 'm5.*')"
  type        = list(string)
  default = [
    "t3.*",
    "t3a.*",
    "m5.*",
    "m5a.*",
    "c5.*",
    "c5a.*",
    "r5.*",
    "r5a.*"
  ]
}

variable "require_imdsv2" {
  description = "Require Instance Metadata Service v2 for EC2 instances"
  type        = bool
  default     = true
}

# ============================================================================
# STORAGE AND DATA PROTECTION
# ============================================================================

variable "require_ebs_encryption" {
  description = "Require encryption for all EBS volumes"
  type        = bool
  default     = true
}

variable "protect_s3_buckets" {
  description = "Prevent deletion of S3 buckets"
  type        = bool
  default     = false
}

variable "require_s3_versioning" {
  description = "Require versioning for S3 buckets"
  type        = bool
  default     = false
}

# ============================================================================
# DATABASE PROTECTION
# ============================================================================

variable "require_rds_encryption" {
  description = "Require encryption for RDS instances and clusters"
  type        = bool
  default     = true
}

variable "deny_rds_public_access" {
  description = "Prevent RDS instances from being publicly accessible"
  type        = bool
  default     = true
}

# ============================================================================
# NETWORK SECURITY
# ============================================================================

variable "protect_vpc_resources" {
  description = "Protect VPC resources from unauthorized changes"
  type        = bool
  default     = false
}

variable "vpc_admin_roles" {
  description = "List of IAM role ARNs allowed to modify VPC resources"
  type        = list(string)
  default     = []
}

variable "deny_internet_gateway" {
  description = "Prevent creation of internet gateways (for isolated environments)"
  type        = bool
  default     = false
}

variable "require_vpc_flow_logs" {
  description = "Prevent deletion of VPC Flow Logs"
  type        = bool
  default     = true
}

# ============================================================================
# IAM AND SECURITY SERVICES
# ============================================================================

variable "protect_security_hub" {
  description = "Prevent disabling or removing Security Hub"
  type        = bool
  default     = true
}

variable "protect_guardduty" {
  description = "Prevent disabling or removing GuardDuty"
  type        = bool
  default     = true
}

variable "enforce_sso_only" {
  description = "Prevent creation of IAM users to enforce SSO"
  type        = bool
  default     = false
}

# ============================================================================
# COST MANAGEMENT
# ============================================================================

variable "restrict_expensive_resources" {
  description = "Prevent launching expensive instance types"
  type        = bool
  default     = false
}

variable "protect_reserved_instances" {
  description = "Prevent modification or deletion of Reserved Instances"
  type        = bool
  default     = false
}

variable "billing_admin_roles" {
  description = "List of IAM role ARNs allowed to modify Reserved Instances"
  type        = list(string)
  default     = []
}

# ============================================================================
# POLICY ATTACHMENTS
# ============================================================================

variable "policy_attachments" {
  description = "Map of policy attachments to organizational units"
  type = map(object({
    policy_name  = string
    target_ou_id = string
  }))
  default = {}
  
  # Example:
  # {
  #   "prod-require-encryption" = {
  #     policy_name  = "RequireEBSEncryption"
  #     target_ou_id = "ou-xxxx-xxxxxxxx"
  #   }
  # }
}
