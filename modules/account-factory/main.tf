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

# Configure account resources using AWS CLI with assumed role
resource "null_resource" "configure_account" {
  depends_on = [time_sleep.account_setup]
  
  triggers = {
    account_id = aws_organizations_account.developer_account.id
    always_run = timestamp()
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "Assuming role in account ${aws_organizations_account.developer_account.id}..."
      CREDS=$(aws sts assume-role \
        --role-arn arn:aws:iam::${aws_organizations_account.developer_account.id}:role/OrganizationAccountAccessRole \
        --role-session-name terraform-setup \
        --duration-seconds 3600 \
        --output json)
      
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
      export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')
      
      echo "Creating S3 bucket..."
      aws s3api create-bucket \
        --bucket bose-dev-${var.developer_name}-terraform-state \
        --region ${var.aws_region} \
        $(if [ "${var.aws_region}" != "us-east-1" ]; then echo "--create-bucket-configuration LocationConstraint=${var.aws_region}"; fi) || echo "Bucket may already exist"
      
      echo "Enabling versioning..."
      aws s3api put-bucket-versioning \
        --bucket bose-dev-${var.developer_name}-terraform-state \
        --versioning-configuration Status=Enabled
      
      echo "Enabling encryption..."
      aws s3api put-bucket-encryption \
        --bucket bose-dev-${var.developer_name}-terraform-state \
        --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
      
      echo "Blocking public access..."
      aws s3api put-public-access-block \
        --bucket bose-dev-${var.developer_name}-terraform-state \
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
      
      echo "Creating DynamoDB table..."
      aws dynamodb create-table \
        --table-name bose-dev-${var.developer_name}-terraform-locks \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region ${var.aws_region} || echo "Table may already exist"
      
      echo "Account configuration complete!"
    EOT
    
    interpreter = ["/bin/bash", "-c"]
  }
}

# Create IAM permission boundary
resource "null_resource" "create_permission_boundary" {
  depends_on = [null_resource.configure_account]
  
  triggers = {
    account_id = aws_organizations_account.developer_account.id
    policy     = local.permission_boundary_policy
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      CREDS=$(aws sts assume-role \
        --role-arn arn:aws:iam::${aws_organizations_account.developer_account.id}:role/OrganizationAccountAccessRole \
        --role-session-name terraform-setup \
        --output json)
      
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
      export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')
      
      cat > /tmp/permission-boundary-${var.developer_name}.json << 'POLICY'
${local.permission_boundary_policy}
POLICY
      
      echo "Creating permission boundary policy..."
      aws iam create-policy \
        --policy-name DeveloperPermissionBoundary \
        --policy-document file:///tmp/permission-boundary-${var.developer_name}.json \
        --description "Permission boundary for developer accounts" || echo "Policy may already exist"
      
      rm /tmp/permission-boundary-${var.developer_name}.json
    EOT
    
    interpreter = ["/bin/bash", "-c"]
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

# Create developer role
resource "null_resource" "create_developer_role" {
  depends_on = [null_resource.create_permission_boundary]
  
  triggers = {
    account_id = aws_organizations_account.developer_account.id
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      CREDS=$(aws sts assume-role \
        --role-arn arn:aws:iam::${aws_organizations_account.developer_account.id}:role/OrganizationAccountAccessRole \
        --role-session-name terraform-setup \
        --output json)
      
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
      export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')
      
      cat > /tmp/trust-policy-${var.developer_name}.json << 'TRUST'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${var.management_account_id}:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
TRUST
      
      echo "Creating developer role..."
      aws iam create-role \
        --role-name DeveloperRole \
        --assume-role-policy-document file:///tmp/trust-policy-${var.developer_name}.json \
        --permissions-boundary arn:aws:iam::${aws_organizations_account.developer_account.id}:policy/DeveloperPermissionBoundary || echo "Role may already exist"
      
      echo "Attaching PowerUserAccess policy..."
      aws iam attach-role-policy \
        --role-name DeveloperRole \
        --policy-arn arn:aws:iam::aws:policy/PowerUserAccess || echo "Policy may already be attached"
      
      rm /tmp/trust-policy-${var.developer_name}.json
    EOT
    
    interpreter = ["/bin/bash", "-c"]
  }
}

# Create budget
resource "null_resource" "create_budget" {
  depends_on = [null_resource.configure_account]
  
  triggers = {
    account_id   = aws_organizations_account.developer_account.id
    budget_limit = var.budget_limit
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      cat > /tmp/budget-${var.developer_name}.json << 'BUDGET'
{
  "BudgetName": "bose-dev-${var.developer_name}-monthly-budget",
  "BudgetType": "COST",
  "TimeUnit": "MONTHLY",
  "BudgetLimit": {
    "Amount": "${var.budget_limit}",
    "Unit": "USD"
  },
  "CostFilters": {
    "LinkedAccount": ["${aws_organizations_account.developer_account.id}"]
  }
}
BUDGET
      
      cat > /tmp/notifications-${var.developer_name}.json << 'NOTIF'
[
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "EMAIL",
        "Address": "${var.developer_email}"
      },
      {
        "SubscriptionType": "EMAIL",
        "Address": "${var.admin_email}"
      }
    ]
  },
  {
    "Notification": {
      "NotificationType": "FORECASTED",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 90,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "EMAIL",
        "Address": "${var.developer_email}"
      },
      {
        "SubscriptionType": "EMAIL",
        "Address": "${var.admin_email}"
      }
    ]
  }
]
NOTIF
      
      echo "Creating budget..."
      aws budgets create-budget \
        --account-id ${aws_organizations_account.developer_account.id} \
        --budget file:///tmp/budget-${var.developer_name}.json \
        --notifications-with-subscribers file:///tmp/notifications-${var.developer_name}.json || echo "Budget may already exist"
      
      rm /tmp/budget-${var.developer_name}.json
      rm /tmp/notifications-${var.developer_name}.json
    EOT
    
    interpreter = ["/bin/bash", "-c"]
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
