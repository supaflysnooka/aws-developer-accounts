# environments/dev-accounts/main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "boseprofessional-org-terraform-state"
    key            = "dev-accounts/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "boseprofessional-org-terraform-locks"
    encrypt        = true
  }
}

# Management account provider
provider "aws" {
  alias  = "management"
  region = var.aws_region
}

# Provider for each developer account will be configured dynamically
provider "aws" {
  alias  = "john_smith_account"
  region = var.aws_region
  
  assume_role {
    role_arn = "arn:aws:iam::${module.john_smith_account.account_id}:role/OrganizationAccountAccessRole"
  }
}

# Create individual developer accounts
module "john_smith_account" {
  source = "../../modules/account-factory"
  
  providers = {
    aws                = aws.management
    aws.target_account = aws.john_smith_account
  }
  
  developer_name       = "john-smith"
  developer_email      = "john.smith@boseprofessional.com"
  budget_limit         = 100
  jira_ticket_id      = "INFRA-123"
  management_account_id = data.aws_caller_identity.current.account_id
}

module "jane_doe_account" {
  source = "../../modules/account-factory"
  
  providers = {
    aws                = aws.management
    aws.target_account = aws.jane_doe_account
  }
  
  developer_name       = "jane-doe"
  developer_email      = "jane.doe@boseprofessional.com"
  budget_limit         = 150
  jira_ticket_id      = "INFRA-124"
  management_account_id = data.aws_caller_identity.current.account_id
}

# Data source to get current account ID
data "aws_caller_identity" "current" {
  provider = aws.management
}

# Variables
variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-west-2"
}

# Outputs
output "developer_accounts" {
  description = "Summary of created developer accounts"
  value = {
    john_smith = {
      account_id     = module.john_smith_account.account_id
      state_bucket   = module.john_smith_account.terraform_state_bucket
      role_arn      = module.john_smith_account.developer_role_arn
      onboarding_doc = module.john_smith_account.onboarding_doc_path
    }
    jane_doe = {
      account_id     = module.jane_doe_account.account_id
      state_bucket   = module.jane_doe_account.terraform_state_bucket
      role_arn      = module.jane_doe_account.developer_role_arn
      onboarding_doc = module.jane_doe_account.onboarding_doc_path
    }
  }
}

# GitHub Actions workflow for this
# .github/workflows/dev-accounts.yml
name: Developer Accounts Management

on:
  pull_request:
    paths: ['environments/dev-accounts/**']
  push:
    branches: [main]
    paths: ['environments/dev-accounts/**']

jobs:
  terraform:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: environments/dev-accounts
        
    permissions:
      id-token: write
      contents: read
      pull-requests: write
      
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v3
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
          
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.0
          
      - name: Terraform Init
        run: terraform init
        
      - name: Terraform Validate
        run: terraform validate
        
      - name: Terraform Plan
        id: plan
        run: |
          terraform plan -no-color -out=tfplan
          terraform show -no-color tfplan > plan.txt
        continue-on-error: true
        
      - name: Comment Plan on PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('environments/dev-accounts/plan.txt', 'utf8');
            const body = `## Terraform Plan
            
            \`\`\`
            ${plan}
            \`\`\`
            
            Plan Status: ${{ steps.plan.outcome }}`;
            
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: body
            });
            
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && steps.plan.outcome == 'success'
        run: terraform apply tfplan
        
      - name: Generate Account Summary
        if: github.ref == 'refs/heads/main'
        run: |
          terraform output -json developer_accounts > account_summary.json
          echo "Generated account summary in account_summary.json"
