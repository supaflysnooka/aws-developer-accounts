terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "test_vpc" {
  source = "../../../modules/networking/vpc"
  
  vpc_name           = "test-vpc"
  vpc_cidr          = "10.100.0.0/16"
  availability_zones = ["usw2-az1", "usw2-az2"]
  
  enable_nat_gateway = true
  single_nat_gateway = true
}

output "vpc_id" {
  value = module.test_vpc.vpc_id
}

output "public_subnets" {
  value = module.test_vpc.public_subnets
}
