# modules/account-factory/variables.tf
variable "developer_name" {
  description = "Name of the developer (used in account naming)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.developer_name))
    error_message = "Developer name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "developer_email" {
  description = "Email address for the developer account"
  type        = string
  validation {
    condition     = can(regex("^[\\w\\.+-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", var.developer_email)) 
    error_message = "Must be a valid email address."
  }
}

variable "admin_email" {
  description = "Email address for admin notifications"
  type        = string
  default     = "infrastructure-team@boseprofessional.com"
}

variable "budget_limit" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 100
  validation {
    condition     = var.budget_limit > 0 && var.budget_limit <= 1000
    error_message = "Budget limit must be between 1 and 1000 USD."
  }
}

variable "jira_ticket_id" {
  description = "Jira ticket ID for account request tracking"
  type        = string
  default     = ""
}

variable "management_account_id" {
  description = "AWS Organizations management account ID"
  type        = string
}

variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-west-2"
}

variable "aws_profile" {
  description = "AWS profile to use for AWS CLI commands"
  type        = string
  default     = ""
}

variable "allowed_regions" {
  description = "List of AWS regions the developer can use"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "allowed_instance_types" {
  description = "List of allowed EC2 instance types"
  type        = list(string)
  default     = [
    "t3.nano", "t3.micro", "t3.small", "t3.medium",
    "t4g.nano", "t4g.micro", "t4g.small", "t4g.medium"
  ]
}

variable "vpc_cidr_block" {
  description = "CIDR block for the developer VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones for the VPC"
  type        = list(string)
  default     = ["usw2-az1", "usw2-az2"]
}
