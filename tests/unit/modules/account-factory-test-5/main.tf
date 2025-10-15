# Get current account ID
data "aws_caller_identity" "current" {}

# Random ID for unique naming
resource "random_id" "test" {
  byte_length = 4
}

# Declare the variable HERE in the test directory
variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
}

# Create test developer account
module "test_account" {
  source = "../../../../modules/account-factory"
  
  developer_name        = "rob-birdwell-${random_id.test.hex}"
  developer_email       = "rob.birdwell+test${random_id.test.hex}@boseprofessional.com"
  budget_limit          = 100
  jira_ticket_id        = "TEST-001"
  management_account_id = data.aws_caller_identity.current.account_id
  aws_profile           = var.aws_profile
}

# Outputs
output "account_id" {
  value = module.test_account.account_id
}

output "account_email" {
  value = module.test_account.account_email
}

output "state_bucket" {
  value = module.test_account.terraform_state_bucket
}

output "developer_role_arn" {
  value = module.test_account.developer_role_arn
}
