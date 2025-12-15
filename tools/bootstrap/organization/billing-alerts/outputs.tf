output "sns_topic_arn" {
  description = "ARN of the billing alerts SNS topic"
  value       = aws_sns_topic.billing_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the billing alerts SNS topic"
  value       = aws_sns_topic.billing_alerts.name
}

output "monthly_budget_name" {
  description = "Name of the monthly budget"
  value       = var.enable_monthly_budget ? aws_budgets_budget.monthly_total[0].name : null
}

output "monthly_budget_id" {
  description = "ID of the monthly budget"
  value       = var.enable_monthly_budget ? aws_budgets_budget.monthly_total[0].id : null
}

output "service_budget_names" {
  description = "Names of service-specific budgets"
  value       = { for k, v in aws_budgets_budget.service_budgets : k => v.name }
}

output "tag_budget_names" {
  description = "Names of tag-based budgets"
  value       = { for k, v in aws_budgets_budget.tag_budgets : k => v.name }
}

output "daily_spend_alarm_name" {
  description = "Name of the daily spend CloudWatch alarm"
  value       = var.enable_daily_spend_alarm ? aws_cloudwatch_metric_alarm.daily_spend[0].alarm_name : null
}

output "daily_spend_alarm_arn" {
  description = "ARN of the daily spend CloudWatch alarm"
  value       = var.enable_daily_spend_alarm ? aws_cloudwatch_metric_alarm.daily_spend[0].arn : null
}

output "service_alarm_names" {
  description = "Names of service-specific spend alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.service_spend : k => v.alarm_name }
}

output "anomaly_monitor_arn" {
  description = "ARN of the cost anomaly monitor"
  value       = var.enable_anomaly_detection ? aws_ce_anomaly_monitor.billing_anomalies[0].arn : null
}

output "anomaly_subscription_arn" {
  description = "ARN of the cost anomaly subscription"
  value       = var.enable_anomaly_detection ? aws_ce_anomaly_subscription.billing_anomalies[0].arn : null
}

output "billing_dashboard_name" {
  description = "Name of the billing CloudWatch dashboard"
  value       = var.create_billing_dashboard ? aws_cloudwatch_dashboard.billing[0].dashboard_name : null
}

output "budget_action_role_arn" {
  description = "ARN of the budget action IAM role"
  value       = var.enable_budget_actions ? aws_iam_role.budget_action[0].arn : null
}

output "budget_configuration" {
  description = "Summary of budget configuration"
  value = {
    monthly_budget_enabled       = var.enable_monthly_budget
    monthly_budget_limit         = var.monthly_budget_limit
    service_budgets_count        = length(var.service_budgets)
    tag_budgets_count            = length(var.tag_budgets)
    anomaly_detection_enabled    = var.enable_anomaly_detection
    daily_spend_alarm_enabled    = var.enable_daily_spend_alarm
    budget_actions_enabled       = var.enable_budget_actions
    dashboard_created            = var.create_billing_dashboard
    alert_email_count            = length(var.alert_email_addresses)
  }
}

output "alert_summary" {
  description = "Summary of configured alerts"
  value = {
    total_budgets         = (var.enable_monthly_budget ? 1 : 0) + length(var.service_budgets) + length(var.tag_budgets)
    total_cloudwatch_alarms = (var.enable_daily_spend_alarm ? 1 : 0) + length(var.service_spend_alarms)
    anomaly_detection     = var.enable_anomaly_detection
    email_subscriptions   = length(var.alert_email_addresses)
  }
}
