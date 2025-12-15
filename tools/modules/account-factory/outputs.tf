# modules/account-factory/outputs.tf
output "account_id" {
  description = "ID of the created AWS account"
  value       = aws_organizations_account.developer_account.id
}

output "account_email" {
  description = "Email associated with the account"
  value       = aws_organizations_account.developer_account.email
}

output "terraform_state_bucket" {
  description = "S3 bucket for Terraform state"
  value       = "bose-dev-${var.developer_name}-terraform-state"
}

output "terraform_lock_table" {
  description = "DynamoDB table for Terraform state locking"
  value       = "bose-dev-${var.developer_name}-terraform-locks"
}

output "developer_role_arn" {
  description = "ARN of the developer IAM role"
  value       = "arn:aws:iam::${aws_organizations_account.developer_account.id}:role/DeveloperRole"
}

output "onboarding_doc_path" {
  description = "Path to onboarding documentation"
  value       = local_file.onboarding_doc.filename
}
