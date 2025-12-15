# modules/account-factory/templates/backend.tf.tpl
terraform {
  backend "s3" {
    bucket         = "${bucket_name}"
    key            = "infrastructure/terraform.tfstate"
    region         = "${region}"
    dynamodb_table = "${dynamodb_table}"
    encrypt        = true
  }
}

# Configure the AWS Provider for your account
provider "aws" {
  region = "${region}"
  
  assume_role {
    role_arn = "arn:aws:iam::${account_id}:role/DeveloperRole"
  }
}
