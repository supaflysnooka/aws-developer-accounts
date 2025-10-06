# modules/account-factory/templates/backend.tf.tpl
terraform {
  backend "s3" {
    bucket         = "bose-dev-rob-birdwell-b8e30df3-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "bose-dev-rob-birdwell-b8e30df3-terraform-locks"
    encrypt        = true
  }
}

# Configure the AWS Provider for your account
provider "aws" {
  region = "us-west-2"
  
  assume_role {
    role_arn = "arn:aws:iam::385003642181:role/DeveloperRole"
  }
}
