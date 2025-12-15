# modules/account-factory/templates/backend.tf.tpl
terraform {
  backend "s3" {
    bucket         = "bose-dev-rob-birdwell-32f185bf-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "bose-dev-rob-birdwell-32f185bf-terraform-locks"
    encrypt        = true
  }
}

# Configure the AWS Provider for your account
provider "aws" {
  region = "us-west-2"
  
  assume_role {
    role_arn = "arn:aws:iam::389170470967:role/DeveloperRole"
  }
}
