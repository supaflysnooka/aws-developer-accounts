# modules/account-factory/main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Detect operating system
locals {
  is_windows = substr(pathexpand("~"), 0, 1) == "/" ? false : true
  is_unix    = !local.is_windows
  
  # Script file extension based on OS
  script_ext = local.is_windows ? "ps1" : "sh"
  
  # Script interpreter based on OS - for file execution
  shell_interpreter = local.is_windows ? ["PowerShell", "-ExecutionPolicy", "Bypass", "-File"] : ["/bin/bash"]
}

# Create the developer account
resource "aws_organizations_account" "developer_account" {
  name      = "bose-dev-${var.developer_name}"
  email     = var.developer_email
  role_name = "OrganizationAccountAccessRole"
  
  tags = {
    Environment  = "development"
    Owner        = var.developer_name
    Type         = "developer-sandbox"
    CreatedBy    = "terraform"
    BudgetLimit  = var.budget_limit
    JiraTicket   = var.jira_ticket_id
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Wait for account to be fully provisioned and role to be available
resource "time_sleep" "account_setup" {
  depends_on      = [aws_organizations_account.developer_account]
  create_duration = "60s"
}

# Generate configure-account script
resource "local_file" "configure_account_script" {
  content = templatefile("${path.module}/scripts/configure-account.${local.script_ext}", {
    account_id     = aws_organizations_account.developer_account.id
    developer_name = var.developer_name
    aws_region     = var.aws_region
  })
  
  filename = "${path.root}/.terraform/tmp/configure-account-${var.developer_name}.${local.script_ext}"
}

# Configure account resources using AWS CLI with assumed role
resource "null_resource" "configure_account" {
  depends_on = [time_sleep.account_setup, local_file.configure_account_script]
  
  triggers = {
    account_id = aws_organizations_account.developer_account.id
    always_run = timestamp()
  }
  
  provisioner "local-exec" {
    command     = local_file.configure_account_script.filename
    interpreter = local.shell_interpreter
    
    environment = {
      AWS_PROFILE = var.aws_profile
    }
  }
}

# Local variable for permission boundary policy
locals {
  permission_boundary_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowedServices"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "ecs:*",
          "eks:*",
          "lambda:*",
          "s3:*",
          "dynamodb:*",
          "rds:*",
          "elasticloadbalancing:*",
          "cloudfront:*",
          "sqs:*",
          "sns:*",
          "cloudwatch:*",
          "logs:*",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetRole",
          "iam:GetPolicy",
          "iam:ListRoles",
          "iam:ListPolicies",
          "iam:PassRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.allowed_regions
          }
        }
      },
      {
        Sid    = "DenyExpensiveInstances"
        Effect = "Deny"
        Action = ["ec2:RunInstances"]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          "ForAnyValue:StringNotEquals" = {
            "ec2:InstanceType" = var.allowed_instance_types
          }
        }
      },
      {
        Sid      = "DenyMarketplace"
        Effect   = "Deny"
        Action   = ["aws-marketplace:*"]
        Resource = "*"
      },
      {
        Sid    = "DenyBilling"
        Effect = "Deny"
        Action = [
          "aws-portal:*",
          "budgets:*",
          "cur:*",
          "organizations:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Generate permission boundary script
resource "local_file" "create_permission_boundary_script" {
  content = templatefile("${path.module}/scripts/create-permission-boundary.${local.script_ext}", {
    account_id     = aws_organizations_account.developer_account.id
    developer_name = var.developer_name
    policy_json    = local.is_windows ? jsonencode(jsondecode(local.permission_boundary_policy)) : local.permission_boundary_policy
  })
  
  filename = "${path.root}/.terraform/tmp/create-permission-boundary-${var.developer_name}.${local.script_ext}"
}

# Create IAM permission boundary
resource "null_resource" "create_permission_boundary" {
  depends_on = [null_resource.configure_account, local_file.create_permission_boundary_script]
  
  triggers = {
    account_id = aws_organizations_account.developer_account.id
    policy     = local.permission_boundary_policy
  }
  
  provisioner "local-exec" {
    command     = local_file.create_permission_boundary_script.filename
    interpreter = local.shell_interpreter
    
    environment = {
      AWS_PROFILE = var.aws_profile
    }
  }
}

# Generate developer role script
resource "local_file" "create_developer_role_script" {
  content = templatefile("${path.module}/scripts/create-developer-role.${local.script_ext}", {
    account_id            = aws_organizations_account.developer_account.id
    developer_name        = var.developer_name
    management_account_id = var.management_account_id
  })
  
  filename = "${path.root}/.terraform/tmp/create-developer-role-${var.developer_name}.${local.script_ext}"
}

# Create developer role
resource "null_resource" "create_developer_role" {
  depends_on = [null_resource.create_permission_boundary, local_file.create_developer_role_script]
  
  triggers = {
    account_id = aws_organizations_account.developer_account.id
  }
  
  provisioner "local-exec" {
    command     = local_file.create_developer_role_script.filename
    interpreter = local.shell_interpreter
    
    environment = {
      AWS_PROFILE = var.aws_profile
    }
  }
}

# Generate budget script
resource "local_file" "create_budget_script" {
  content = templatefile("${path.module}/scripts/create-budget.${local.script_ext}", {
    account_id      = aws_organizations_account.developer_account.id
    developer_name  = var.developer_name
    budget_limit    = var.budget_limit
    developer_email = var.developer_email
    admin_email     = var.admin_email
  })
  
  filename = "${path.root}/.terraform/tmp/create-budget-${var.developer_name}.${local.script_ext}"
}

# Create budget
resource "null_resource" "create_budget" {
  depends_on = [null_resource.configure_account, local_file.create_budget_script]
  
  triggers = {
    account_id   = aws_organizations_account.developer_account.id
    budget_limit = var.budget_limit
  }
  
  provisioner "local-exec" {
    command     = local_file.create_budget_script.filename
    interpreter = local.shell_interpreter
    
    environment = {
      AWS_PROFILE = var.aws_profile
    }
  }
}

# Generate backend configuration file
resource "local_file" "backend_config" {
  depends_on = [null_resource.configure_account]
  
  content = templatefile("${path.module}/templates/backend.tf.tpl", {
    bucket_name    = "bose-dev-${var.developer_name}-terraform-state"
    dynamodb_table = "bose-dev-${var.developer_name}-terraform-locks"
    region         = var.aws_region
    developer_name = var.developer_name
    account_id     = aws_organizations_account.developer_account.id
  })
  
  filename = "${path.root}/generated/${var.developer_name}/backend.tf"
}

# Generate onboarding documentation
resource "local_file" "onboarding_doc" {
  depends_on = [null_resource.create_developer_role]
  
  content = templatefile("${path.module}/templates/onboarding.md.tpl", {
    developer_name = var.developer_name
    account_id     = aws_organizations_account.developer_account.id
    role_arn       = "arn:aws:iam::${aws_organizations_account.developer_account.id}:role/DeveloperRole"
    bucket_name    = "bose-dev-${var.developer_name}-terraform-state"
    budget_limit   = var.budget_limit
  })
  
  filename = "${path.root}/generated/${var.developer_name}/onboarding.md"
}