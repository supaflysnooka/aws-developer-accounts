# AWS Billing Alerts and Budget Monitoring
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # backend "s3" {
  #   bucket         = "your-bucket-name"
  #   key            = "bootstrap/billing-alerts/terraform.tfstate"
  #   region         = "us-west-2"
  #   dynamodb_table = "terraform-state-locks"
  #   encrypt        = true
  # }
}

# Provider for us-east-1 (required for billing metrics and budgets)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  region = var.region
}

# ============================================================================
# SNS TOPICS FOR ALERTS
# ============================================================================

# SNS topic for billing alerts (must be in us-east-1)
resource "aws_sns_topic" "billing_alerts" {
  provider = aws.us_east_1
  
  name         = var.billing_alert_topic_name
  display_name = "AWS Billing Alerts"
  
  kms_master_key_id = var.kms_key_id
  
  tags = merge(
    var.tags,
    {
      Name    = var.billing_alert_topic_name
      Purpose = "billing-alerts"
    }
  )
}

resource "aws_sns_topic_policy" "billing_alerts" {
  provider = aws.us_east_1
  
  arn = aws_sns_topic.billing_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBudgetsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.billing_alerts.arn
      },
      {
        Sid    = "AllowCloudWatchToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.billing_alerts.arn
      }
    ]
  })
}

# Email subscriptions
resource "aws_sns_topic_subscription" "billing_emails" {
  provider = aws.us_east_1
  
  count     = length(var.alert_email_addresses)
  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email_addresses[count.index]
}

# ============================================================================
# AWS BUDGETS
# ============================================================================

# Monthly total budget
resource "aws_budgets_budget" "monthly_total" {
  count = var.enable_monthly_budget ? 1 : 0
  
  name              = var.monthly_budget_name
  budget_type       = "COST"
  limit_amount      = var.monthly_budget_limit
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = var.budget_start_date
  
  cost_filter {
    name = "RecordType"
    values = [
      "Usage",
      "Tax",
      "Support"
    ]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.billing_alerts.arn]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.billing_alerts.arn]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 90
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.billing_alerts.arn]
  }
}

# Service-specific budgets
resource "aws_budgets_budget" "service_budgets" {
  for_each = var.service_budgets
  
  name              = "budget-${each.key}"
  budget_type       = "COST"
  limit_amount      = each.value.limit
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = var.budget_start_date
  
  cost_filter {
    name   = "Service"
    values = [each.value.service_name]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = each.value.threshold_percentage
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.billing_alerts.arn]
  }
}

# Tag-based budgets (e.g., per-environment)
resource "aws_budgets_budget" "tag_budgets" {
  for_each = var.tag_budgets
  
  name              = "budget-tag-${each.key}"
  budget_type       = "COST"
  limit_amount      = each.value.limit
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = var.budget_start_date
  
  cost_filter {
    name   = "TagKeyValue"
    values = ["${each.value.tag_key}$${each.value.tag_value}"]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = each.value.threshold_percentage
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.billing_alerts.arn]
  }
}

# Savings Plans coverage budget
resource "aws_budgets_budget" "savings_plan_coverage" {
  count = var.enable_savings_plan_coverage ? 1 : 0
  
  name         = "savings-plan-coverage"
  budget_type  = "SAVINGS_PLANS_COVERAGE"
  limit_amount = var.savings_plan_coverage_threshold
  limit_unit   = "PERCENTAGE"
  time_unit    = "MONTHLY"
  
  notification {
    comparison_operator        = "LESS_THAN"
    threshold                  = var.savings_plan_coverage_threshold
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.billing_alerts.arn]
  }
}

# Reserved Instance utilization budget
resource "aws_budgets_budget" "ri_utilization" {
  count = var.enable_ri_utilization ? 1 : 0
  
  name         = "ri-utilization"
  budget_type  = "RI_UTILIZATION"
  limit_amount = var.ri_utilization_threshold
  limit_unit   = "PERCENTAGE"
  time_unit    = "MONTHLY"
  
  notification {
    comparison_operator        = "LESS_THAN"
    threshold                  = var.ri_utilization_threshold
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.billing_alerts.arn]
  }
}

# ============================================================================
# CLOUDWATCH BILLING ALARMS
# ============================================================================

# Daily spend alarm
resource "aws_cloudwatch_metric_alarm" "daily_spend" {
  provider = aws.us_east_1
  
  count = var.enable_daily_spend_alarm ? 1 : 0
  
  alarm_name          = "billing-daily-spend-exceeds-threshold"
  alarm_description   = "Alert when estimated daily charges exceed threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 86400  # 24 hours
  statistic           = "Maximum"
  threshold           = var.daily_spend_threshold
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    Currency = "USD"
  }
  
  alarm_actions = [aws_sns_topic.billing_alerts.arn]
  ok_actions    = [aws_sns_topic.billing_alerts.arn]
  
  tags = merge(
    var.tags,
    {
      Name = "Daily Spend Alarm"
    }
  )
}

# Service-specific spend alarms
resource "aws_cloudwatch_metric_alarm" "service_spend" {
  provider = aws.us_east_1
  
  for_each = var.service_spend_alarms
  
  alarm_name          = "billing-${each.key}-spend-exceeds-threshold"
  alarm_description   = "Alert when ${each.key} charges exceed threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 21600  # 6 hours
  statistic           = "Maximum"
  threshold           = each.value.threshold
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    Currency    = "USD"
    ServiceName = each.value.service_name
  }
  
  alarm_actions = [aws_sns_topic.billing_alerts.arn]
  
  tags = merge(
    var.tags,
    {
      Name    = "${each.key} Spend Alarm"
      Service = each.value.service_name
    }
  )
}

# Anomaly detector for unusual spending patterns
resource "aws_ce_anomaly_monitor" "billing_anomalies" {
  count = var.enable_anomaly_detection ? 1 : 0
  
  name              = "billing-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
  
  tags = merge(
    var.tags,
    {
      Name = "Billing Anomaly Monitor"
    }
  )
}

resource "aws_ce_anomaly_subscription" "billing_anomalies" {
  count = var.enable_anomaly_detection ? 1 : 0
  
  name      = "billing-anomaly-subscription"
  frequency = "DAILY"
  
  monitor_arn_list = [
    aws_ce_anomaly_monitor.billing_anomalies[0].arn
  ]
  
  subscriber {
    type    = "SNS"
    address = aws_sns_topic.billing_alerts.arn
  }
  
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = [tostring(var.anomaly_threshold_amount)]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }
  
  tags = merge(
    var.tags,
    {
      Name = "Billing Anomaly Subscription"
    }
  )
}

# ============================================================================
# COST EXPLORER AND REPORTING
# ============================================================================

# CloudWatch Dashboard for billing metrics
resource "aws_cloudwatch_dashboard" "billing" {
  count = var.create_billing_dashboard ? 1 : 0
  
  dashboard_name = var.billing_dashboard_name
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", { stat = "Maximum", label = "Total Estimated Charges" }]
          ]
          period = 21600
          stat   = "Maximum"
          region = "us-east-1"
          title  = "Total Estimated AWS Charges"
          yAxis = {
            left = {
              label = "USD"
            }
          }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            for service in var.dashboard_services : [
              "AWS/Billing",
              "EstimatedCharges",
              {
                stat        = "Maximum"
                label       = service
                dimensions  = { ServiceName = service }
              }
            ]
          ]
          period = 21600
          stat   = "Maximum"
          region = "us-east-1"
          title  = "Service Costs"
          yAxis = {
            left = {
              label = "USD"
            }
          }
        }
      }
    ]
  })
}

# ============================================================================
# BUDGETS ACTION (AUTO-RESPONSE)
# ============================================================================

# Budget action to stop EC2 instances when budget exceeded
resource "aws_budgets_budget_action" "stop_ec2" {
  count = var.enable_budget_actions ? 1 : 0
  
  budget_name        = aws_budgets_budget.monthly_total[0].name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = var.budget_action_approval_required ? "MANUAL" : "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budget_action[0].arn
  
  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = var.budget_action_threshold
  }
  
  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.budget_action_deny[0].arn
      roles      = var.budget_action_target_roles
    }
  }
  
  subscriber {
    address           = aws_sns_topic.billing_alerts.arn
    subscription_type = "SNS"
  }
}

# IAM role for budget actions
resource "aws_iam_role" "budget_action" {
  count = var.enable_budget_actions ? 1 : 0
  
  name = "BudgetActionRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "budget_action" {
  count = var.enable_budget_actions ? 1 : 0
  
  role       = aws_iam_role.budget_action[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSBudgetsActionsRolePolicyForResourceAdministrationWithSSM"
}

# Deny policy to apply when budget exceeded
resource "aws_iam_policy" "budget_action_deny" {
  count = var.enable_budget_actions ? 1 : 0
  
  name        = "BudgetExceededDenyPolicy"
  description = "Denies expensive operations when budget is exceeded"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyExpensiveOperations"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "ec2:StartInstances",
          "rds:CreateDBInstance",
          "rds:CreateDBCluster",
          "elasticache:CreateCacheCluster",
          "redshift:CreateCluster"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = var.tags
}
