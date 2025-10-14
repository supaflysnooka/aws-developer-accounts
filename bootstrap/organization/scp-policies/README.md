# AWS Billing Alerts and Budget Monitoring

This Terraform module creates comprehensive billing alerts, budgets, and cost monitoring for AWS accounts using AWS Budgets, CloudWatch alarms, and Cost Anomaly Detection.

## Purpose

This module helps you:
- Monitor AWS spending against budgets
- Receive alerts before budget overruns
- Detect unusual spending patterns
- Track service-specific costs
- Monitor Reserved Instance and Savings Plans utilization
- Optionally take automated actions when budgets are exceeded

## Features

### AWS Budgets
- **Monthly Total Budget**: Overall spending limit with 80%, 90%, and 100% thresholds
- **Service-Specific Budgets**: Per-service cost limits (EC2, RDS, S3, etc.)
- **Tag-Based Budgets**: Per-environment or per-project budgets
- **Savings Plans Coverage**: Monitor Savings Plans coverage percentage
- **RI Utilization**: Track Reserved Instance utilization
- **Forecasted Alerts**: Get notified when projected to exceed budget

### CloudWatch Alarms
- **Daily Spend Alarm**: Alert on daily spending thresholds
- **Service-Specific Alarms**: Per-service spending alerts
- **Fast Detection**: Alerts as charges accrue (6-hour evaluation)

### Cost Anomaly Detection
- **Machine Learning**: AWS AI detects unusual spending patterns
- **Service-Level Detection**: Identifies which service is anomalous
- **Configurable Thresholds**: Set minimum anomaly amount to alert

### Visualization
- **CloudWatch Dashboard**: Real-time view of costs by service
- **Historical Trends**: Track spending over time
- **Multi-Service View**: Compare costs across services

### Automated Actions (Optional)
- **Budget Actions**: Automatically apply IAM policies when budget exceeded
- **Preventive Controls**: Block expensive operations when over budget
- **Approval Workflows**: Require manual approval for actions

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ AWS Budgets (us-east-1)                             │
│  - Monthly Total                                    │
│  - Service Budgets                                  │
│  - Tag Budgets                                      │
│  - RI/Savings Plans                                 │
└─────────────────┬───────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│ CloudWatch Alarms (us-east-1)                       │
│  - Daily Spend                                      │
│  - Service Spend                                    │
└─────────────────┬───────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│ Cost Anomaly Detection                              │
│  - ML-based detection                               │
│  - Service-level monitoring                         │
└─────────────────┬───────────────────────────────────┘
                  │
                  │ All alerts to:
                  ▼
┌─────────────────────────────────────────────────────┐
│ SNS Topic → Email Subscriptions                     │
└─────────────────────────────────────────────────────┘
```

## Important Notes

### Region Requirement

**CRITICAL**: AWS billing metrics and budgets MUST be created in us-east-1 region. This module handles this automatically using provider aliases.

### Email Confirmation

After deployment, subscribers must confirm email subscriptions:
1. Check email inbox
2. Click "Confirm subscription" link
3. You'll start receiving alerts after confirmation

### Billing Data Delay

- AWS billing data has a delay of 6-24 hours
- Budget alerts check every 8-12 hours
- Real-time alerting is not possible with billing metrics

## Prerequisites

- AWS account with billing access
- Terraform >= 1.5.0
- S3 backend configured
- Email addresses for alerts
- Historical billing data (for anomaly detection)

## Usage

### Basic Configuration

```hcl
module "billing_alerts" {
  source = "./bootstrap/billing-alerts"
  
  region = "us-west-2"  # Primary region (billing metrics still in us-east-1)
  
  # Alert recipients
  alert_email_addresses = [
    "finance@example.com",
    "ops@example.com"
  ]
  
  # Monthly budget
  enable_monthly_budget = true
  monthly_budget_limit  = 10000  # $10,000 USD
  budget_start_date     = "2025-01-01"
  
  # Daily spending alarm
  enable_daily_spend_alarm = true
  daily_spend_threshold    = 350  # ~$10,000 / 30 days
  
  # Anomaly detection
  enable_anomaly_detection  = true
  anomaly_threshold_amount  = 500  # Alert if anomaly > $500
  
  # Dashboard
  create_billing_dashboard = true
}
```

### Comprehensive Configuration

```hcl
module "billing_alerts" {
  source = "./bootstrap/billing-alerts"
  
  region = "us-west-2"
  
  # SNS Configuration
  billing_alert_topic_name = "billing-alerts-prod"
  alert_email_addresses = [
    "cfo@example.com",
    "vp-engineering@example.com",
    "devops@example.com"
  ]
  
  # Monthly Budget
  enable_monthly_budget = true
  monthly_budget_limit  = 50000
  monthly_budget_name   = "production-monthly-budget"
  budget_start_date     = "2025-01-01"
  
  # Service-Specific Budgets
  service_budgets = {
    "ec2" = {
      service_name         = "Amazon Elastic Compute Cloud - Compute"
      limit                = 15000
      threshold_percentage = 80
    }
    "rds" = {
      service_name         = "Amazon Relational Database Service"
      limit                = 8000
      threshold_percentage = 85
    }
    "s3" = {
      service_name         = "Amazon Simple Storage Service"
      limit                = 2000
      threshold_percentage = 75
    }
    "cloudfront" = {
      service_name         = "Amazon CloudFront"
      limit                = 5000
      threshold_percentage = 80
    }
  }
  
  # Tag-Based Budgets (per environment)
  tag_budgets = {
    "production" = {
      tag_key              = "Environment"
      tag_value            = "production"
      limit                = 35000
      threshold_percentage = 85
    }
    "staging" = {
      tag_key              = "Environment"
      tag_value            = "staging"
      limit                = 10000
      threshold_percentage = 80
    }
    "development" = {
      tag_key              = "Environment"
      tag_value            = "development"
      limit                = 5000
      threshold_percentage = 75
    }
  }
  
  # Reserved Instances and Savings Plans
  enable_ri_utilization         = true
  ri_utilization_threshold      = 80
  enable_savings_plan_coverage  = true
  savings_plan_coverage_threshold = 85
  
  # CloudWatch Alarms
  enable_daily_spend_alarm = true
  daily_spend_threshold    = 1700  # ~$50,000 / 30 days
  
  service_spend_alarms = {
    "ec2" = {
      service_name = "AmazonEC2"
      threshold    = 500  # Daily
    }
    "rds" = {
      service_name = "AmazonRDS"
      threshold    = 300
    }
  }
  
  # Anomaly Detection
  enable_anomaly_detection = true
  anomaly_threshold_amount = 1000
  
  # Dashboard
  create_billing_dashboard = true
  billing_dashboard_name   = "ProductionBillingOverview"
  dashboard_services = [
    "AmazonEC2",
    "AmazonRDS",
    "AmazonS3",
    "AmazonCloudFront",
    "AWSLambda",
    "AmazonVPC",
    "AmazonDynamoDB"
  ]
  
  # Budget Actions (Optional - use carefully!)
  enable_budget_actions            = false
  budget_action_threshold          = 100
  budget_action_approval_required  = true
  
  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Purpose     = "cost-monitoring"
  }
}
```

### Minimal Cost-Conscious Configuration

For smaller environments:

```hcl
module "billing_alerts" {
  source = "./bootstrap/billing-alerts"
  
  alert_email_addresses = ["admin@example.com"]
  
  # Basic monthly budget
  enable_monthly_budget = true
  monthly_budget_limit  = 500
  
  # Essential monitoring only
  enable_daily_spend_alarm = true
  daily_spend_threshold    = 20
  
  # Skip expensive features
  enable_anomaly_detection     = false
  create_billing_dashboard     = false
  enable_savings_plan_coverage = false
  enable_ri_utilization        = false
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| region | Primary AWS region | string | us-west-2 | no |
| billing_alert_topic_name | SNS topic name | string | billing-alerts | no |
| alert_email_addresses | Email addresses for alerts | list(string) | [] | yes |
| enable_monthly_budget | Enable monthly budget | bool | true | no |
| monthly_budget_limit | Monthly budget in USD | number | 1000 | no |
| budget_start_date | Budget start date (YYYY-MM-DD) | string | 2025-01-01 | no |
| service_budgets | Service-specific budgets | map(object) | {} | no |
| tag_budgets | Tag-based budgets | map(object) | {} | no |
| enable_savings_plan_coverage | Monitor Savings Plans | bool | false | no |
| savings_plan_coverage_threshold | Min coverage % | number | 80 | no |
| enable_ri_utilization | Monitor RI utilization | bool | false | no |
| ri_utilization_threshold | Min RI utilization % | number | 80 | no |
| enable_daily_spend_alarm | Daily spend alarm | bool | true | no |
| daily_spend_threshold | Daily spend threshold USD | number | 50 | no |
| service_spend_alarms | Service spend alarms | map(object) | {} | no |
| enable_anomaly_detection | Enable anomaly detection | bool | true | no |
| anomaly_threshold_amount | Min anomaly amount USD | number | 100 | no |
| create_billing_dashboard | Create dashboard | bool | true | no |
| enable_budget_actions | Enable budget actions | bool | false | no |

## Outputs

| Name | Description |
|------|-------------|
| sns_topic_arn | SNS topic ARN |
| monthly_budget_name | Monthly budget name |
| service_budget_names | Service budget names |
| tag_budget_names | Tag budget names |
| daily_spend_alarm_name | Daily alarm name |
| anomaly_monitor_arn | Anomaly monitor ARN |
| billing_dashboard_name | Dashboard name |
| budget_configuration | Configuration summary |

## Post-Deployment Steps

### 1. Confirm Email Subscriptions

Check your email and confirm all subscriptions:
```
From: AWS Notifications
Subject: AWS Notification - Subscription Confirmation

Click to confirm: [Confirm subscription]
```

### 2. Verify Budget Creation

```bash
# List all budgets
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text)

# Check specific budget
aws budgets describe-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget-name monthly-total-budget
```

### 3. View CloudWatch Dashboard

Navigate to CloudWatch console → Dashboards → BillingOverview

### 4. Test Alert (Optional)

Trigger a test notification:

```bash
SNS_TOPIC_ARN=$(cd bootstrap/billing-alerts && terraform output -raw sns_topic_arn)

aws sns publish \
  --topic-arn $SNS_TOPIC_ARN \
  --subject "Test Billing Alert" \
  --message "This is a test billing notification"
```

## Understanding AWS Service Names

AWS uses specific service names in billing. Here are common ones:

| Friendly Name | AWS Billing Service Name |
|--------------|--------------------------|
| EC2 | Amazon Elastic Compute Cloud - Compute |
| RDS | Amazon Relational Database Service |
| S3 | Amazon Simple Storage Service |
| Lambda | AWS Lambda |
| CloudFront | Amazon CloudFront |
| VPC | Amazon Virtual Private Cloud |
| DynamoDB | Amazon DynamoDB |
| ECS | Amazon EC2 Container Service |
| EKS | Amazon Elastic Container Service for Kubernetes |

Find exact names:
```bash
aws ce get-dimension-values \
  --dimension SERVICE \
  --time-period Start=2025-01-01,End=2025-02-01
```

## Budget Alert Examples

### Monthly Budget Alert Email

```
Subject: AWS Budgets - monthly-total-budget has exceeded 80% of budgeted amount

Dear AWS Customer,

Your budget "monthly-total-budget" has exceeded 80% of your budgeted amount.

Budget Name: monthly-total-budget
Budget Amount: $10,000.00
Actual Spend: $8,234.56 (82.35%)
Time Period: January 2025

Recommendations:
- Review your AWS Cost Explorer
- Identify high-cost resources
- Consider rightsizing or optimization
```

### Anomaly Detection Alert

```
Subject: AWS Cost Anomaly Detection Alert

An anomaly was detected in your AWS spending:

Service: Amazon EC2
Anomaly Impact: $1,234.56
Severity: High
Date: 2025-01-15

Investigate in AWS Cost Anomaly Detection console.
```

## CloudWatch Dashboard

The created dashboard shows:
- Total estimated charges (line graph)
- Per-service costs (multi-line graph)
- 6-hour update frequency
- Historical trend analysis

Access: CloudWatch Console → Dashboards → [dashboard name]

## Budget Actions (Advanced)

Budget actions automatically respond when budgets are exceeded.

### Enable Budget Actions

```hcl
enable_budget_actions = true
budget_action_threshold = 100  # Trigger at 100% of budget
budget_action_approval_required = true  # Manual approval
budget_action_target_roles = [
  "DeveloperRole",
  "DataScientistRole"
]
```

### How Budget Actions Work

1. Budget threshold exceeded (e.g., 100%)
2. AWS applies IAM policy to specified roles
3. Policy denies expensive operations
4. Notification sent to SNS topic
5. (Optional) Manual approval required to apply

### Budget Action Policy

The module creates a deny policy that blocks:
- EC2 RunInstances and StartInstances
- RDS CreateDBInstance and CreateDBCluster
- ElastiCache CreateCacheCluster
- Redshift CreateCluster

### Warning About Budget Actions

Budget actions are powerful but risky:
- Can block legitimate work
- May impact production if misconfigured
- No "dry-run" mode
- Difficult to reverse quickly

**Recommendation**: Use manual approval and test in non-production first.

## Cost Optimization Tips

### Reduce False Positives

```hcl
# Set realistic thresholds
monthly_budget_limit = 12000  # Based on historical average
anomaly_threshold_amount = 500  # Ignore small anomalies

# Use service-specific budgets
service_budgets = {
  "ec2" = {
    limit = 8000
    threshold_percentage = 90  # Higher threshold for expected variability
  }
}
```

### Tag-Based Cost Allocation

```hcl
tag_budgets = {
  "team-a" = {
    tag_key   = "Team"
    tag_value = "TeamA"
    limit     = 5000
    threshold_percentage = 85
  }
}
```

Ensure resources are tagged:
```bash
aws resourcegroupstaggingapi tag-resources \
  --resource-arn-list arn:aws:ec2:us-west-2:123456789012:instance/i-1234567890abcdef0 \
  --tags Team=TeamA,Environment=production
```

## Troubleshooting

### Email Notifications Not Received

1. **Check confirmation**: Email must be confirmed
2. **Check spam folder**: AWS emails may be filtered
3. **Verify subscription**:
```bash
aws sns list-subscriptions-by-topic --topic-arn <topic-arn>
```
4. **Test manually**:
```bash
aws sns publish --topic-arn <topic-arn> --message "Test"
```

### Budget Not Triggering

1. **Check budget thresholds**: May not be exceeded yet
2. **Verify budget period**: Monthly budgets reset each month
3. **Check billing data delay**: Can be 6-24 hours
4. **Review budget filters**:
```bash
aws budgets describe-budget --account-id <account-id> --budget-name <budget-name>
```

### Anomaly Detection Not Working

Requirements for anomaly detection:
- At least 10 days of billing data
- Consistent spending patterns
- Minimum anomaly threshold met

Check monitor status:
```bash
aws ce get-anomaly-monitors
aws ce get-anomalies --date-interval Start=2025-01-01,End=2025-01-31
```

### Dashboard Shows No Data

- Billing metrics require opt-in: AWS Console → Billing → Preferences → Receive Billing Alerts
- Data delay: Wait 6-24 hours after enabling
- Region: Dashboard must query us-east-1 for billing metrics

## Cost of This Module

This module itself has costs:

- **AWS Budgets**: First 2 budgets free, then $0.02 per budget per day (~$0.60/month)
- **CloudWatch Alarms**: $0.10 per alarm per month
- **SNS**: First 1,000 notifications free, then $0.50 per million
- **Cost Anomaly Detection**: No charge
- **CloudWatch Dashboard**: $3.00 per month

**Estimated total**: $5-15/month depending on configuration

**Value**: Can save hundreds or thousands by preventing budget overruns!

## Maintenance

### Monthly Tasks

- Review budget vs actual spending
- Adjust budgets based on trends
- Update service budgets for new services
- Check anomaly detection accuracy

### Quarterly Tasks

- Review and optimize alert thresholds
- Update email distribution list
- Audit tag-based budgets
- Review dashboard usefulness

### Annual Tasks

- Set budgets for new fiscal year
- Comprehensive cost optimization review
- Update budget action policies
- Review savings plans and RI coverage

## Integration with Cost Management Tools

### Export to Spreadsheet

```bash
aws ce get-cost-and-usage \
  --time-period Start=2025-01-01,End=2025-01-31 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output json > costs.json
```

### Cost Explorer Integration

Use Cost Explorer for:
- Detailed cost breakdown
- Forecast analysis
- Reservation recommendations
- Savings opportunities

### Third-Party Tools

This module complements tools like:
- CloudHealth
- CloudCheckr
- Spot.io
- Vantage
- Kubecost (for Kubernetes)

## Security Considerations

- SNS topic can be encrypted with KMS
- Budget data is sensitive financial information
- Restrict access to billing alerts
- Use IAM policies to control budget access

## Related Documentation

- [AWS Budgets Documentation](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/budgets-managing-costs.html)
- [AWS Cost Anomaly Detection](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/manage-ad.html)
- [CloudWatch Billing Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html)
- [AWS Cost Management](https://aws.amazon.com/aws-cost-management/)

## Next Steps

After deploying billing alerts:
1. Confirm all email subscriptions
2. Monitor alerts for first month
3. Adjust thresholds based on actual spending
4. Set up cost allocation tags
5. Review Cost Explorer for optimization opportunities
6. Consider Savings Plans or Reserved Instances
7. Implement FinOps practices across teams
