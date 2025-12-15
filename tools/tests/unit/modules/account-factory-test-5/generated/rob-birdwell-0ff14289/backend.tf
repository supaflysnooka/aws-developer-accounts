# modules/account-factory/templates/backend.tf.tpl
terraform {
  backend "s3" {
    bucket         = "bose-dev-rob-birdwell-0ff14289-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "bose-dev-rob-birdwell-0ff14289-terraform-locks"
    encrypt        = true
  }
}

# Configure the AWS Provider for your account
provider "aws" {
  region = "us-east-2"
  
  assume_role {
    role_arn = "arn:aws:iam::391613010379:role/DeveloperRole"
  }
}
