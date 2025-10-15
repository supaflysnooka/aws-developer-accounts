# modules/account-factory/templates/backend.tf.tpl
terraform {
  backend "s3" {
    bucket         = "bose-dev-robbirdwell-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "bose-dev-robbirdwell-terraform-locks"
    encrypt        = true
  }
}

# Configure the AWS Provider for your account
provider "aws" {
  region = "us-west-2"
  
  assume_role {
    role_arn = "arn:aws:iam::426290730724:role/DeveloperRole"
  }
}
