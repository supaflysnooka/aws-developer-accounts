# Terraform Commands Reference

Quick reference guide for common Terraform commands used across all bootstrap modules.

## Basic Workflow

### Initialize
```bash
# Initialize working directory, download providers
terraform init

# Reinitialize (e.g., after backend config change)
terraform init -reconfigure

# Migrate state to new backend
terraform init -migrate-state

# Upgrade provider versions
terraform init -upgrade
```

### Plan
```bash
# Show execution plan
terraform plan

# Save plan to file
terraform plan -out=tfplan

# Plan with specific variables
terraform plan -var="region=us-west-2" -var="budget_limit=5000"

# Plan with variable file
terraform plan -var-file="production.tfvars"

# Target specific resource
terraform plan -target=aws_s3_bucket.terraform_state
```

### Apply
```bash
# Apply changes
terraform apply

# Apply without confirmation prompt
terraform apply -auto-approve

# Apply saved plan
terraform apply tfplan

# Apply with variables
terraform apply -var="monthly_budget_limit=10000"

# Target specific resource
terraform apply -target=aws_organizations_organizational_unit.production
```

### Destroy
```bash
# Destroy all resources
terraform destroy

# Destroy without confirmation
terraform destroy -auto-approve

# Destroy specific resource
terraform destroy -target=aws_cloudwatch_metric_alarm.daily_spend

# Preview destroy
terraform plan -destroy
```

## State Management

### View State
```bash
# List all resources in state
terraform state list

# Show specific resource
terraform state show aws_s3_bucket.terraform_state

# Show all state in human-readable format
terraform show

# Show state in JSON format
terraform show -json
```

### Modify State
```bash
# Move resource to new address
terraform state mv aws_sns_topic.old aws_sns_topic.new

# Remove resource from state (doesn't delete resource)
terraform state rm aws_cloudwatch_metric_alarm.test

# Replace resource address
terraform state replace-provider registry.terraform.io/-/aws registry.terraform.io/hashicorp/aws

# Import existing resource
terraform import aws_s3_bucket.terraform_state my-bucket-name
```

### State Operations
```bash
# Pull remote state to local file
terraform state pull > terraform.tfstate.backup

# Push local state to remote
terraform state push terraform.tfstate

# Refresh state from real infrastructure
terraform refresh

# Force unlock state (use carefully!)
terraform force-unlock <LOCK_ID>
```

## Output Commands

```bash
# Show all outputs
terraform output

# Show specific output
terraform output sns_topic_arn

# Show output in JSON
terraform output -json

# Show output in raw format (no quotes)
terraform output -raw monthly_budget_limit

# Save outputs to file
terraform output > outputs.txt
```

## Validation and Formatting

```bash
# Validate configuration syntax
terraform validate

# Format configuration files
terraform fmt

# Format recursively
terraform fmt -recursive

# Check if files are formatted
terraform fmt -check

# Show formatting changes
terraform fmt -diff
```

## Workspace Management

```bash
# List workspaces
terraform workspace list

# Show current workspace
terraform workspace show

# Create new workspace
terraform workspace new production

# Switch workspace
terraform workspace select staging

# Delete workspace
terraform workspace delete development
```

## Import Existing Resources

### Common Imports

```bash
# S3 Bucket
terraform import aws_s3_bucket.terraform_state my-bucket-name

# DynamoDB Table
terraform import aws_dynamodb_table.terraform_locks terraform-state-locks

# AWS Organization
terraform import aws_organizations_organization.main o-xxxxxxxxxx

# Organizational Unit
terraform import aws_organizations_organizational_unit.production ou-xxxx-xxxxxxxx

# SCP Policy
terraform import aws_organizations_policy.require_mfa p-xxxxxxxx

# Budget
terraform import aws_budgets_budget.monthly_total 123456789012:monthly-total-budget

# SNS Topic
terraform import aws_sns_topic.billing_alerts arn:aws:sns:us-east-1:123456789012:billing-alerts

# CloudWatch Alarm
terraform import aws_cloudwatch_metric_alarm.daily_spend billing-daily-spend-exceeds-threshold

# Control Tower Landing Zone
terraform import 'aws_controltower_landing_zone.main[0]' landing-zone-id
```

## Troubleshooting Commands

### Debug Mode
```bash
# Enable debug logging
export TF_LOG=DEBUG
terraform apply

# Log to file
export TF_LOG=DEBUG
export TF_LOG_PATH=terraform.log
terraform apply

# Disable logging
unset TF_LOG
unset TF_LOG_PATH
```

### State Issues
```bash
# Check state consistency
terraform validate

# Reconcile state with reality
terraform refresh

# View state lock info
aws dynamodb scan --table-name terraform-state-locks

# Force unlock (if process died)
terraform force-unlock <LOCK_ID>
```

### Dependency Graph
```bash
# Generate dependency graph
terraform graph

# Generate graph as SVG
terraform graph | dot -Tsvg > graph.svg

# Generate graph as PNG
terraform graph | dot -Tpng > graph.png

# Requires graphviz: brew install graphviz (Mac) or apt-get install graphviz (Linux)
```

## Module-Specific Commands

### Terraform Backend Module
```bash
cd bootstrap/terraform-backend

# Initial deployment (local state)
terraform init
terraform apply

# Migrate to remote state
# (after uncommenting backend block in main.tf)
terraform init -migrate-state

# Get backend outputs
terraform output backend_config
```

### Organization Module
```bash
cd bootstrap/organization

# Import existing organization
terraform import aws_organizations_organization.main o-xxxxxxxxxx

# Import existing OU
terraform import aws_organizations_organizational_unit.production ou-xxxx-xxxxxxxx

# Get all OU IDs
terraform output organizational_units

# Get specific OU ID
terraform output ou_production_id
```

### Control Tower Module
```bash
cd bootstrap/control-tower

# Check landing zone status
aws controltower list-landing-zones

# Get landing zone details
terraform output control_tower_status

# Check drift
aws controltower get-landing-zone \
  --landing-zone-identifier $(terraform output -raw landing_zone_id)
```

### SCP Policies Module
```bash
cd bootstrap/scp-policies

# See enabled policies
terraform output enabled_policies

# Get policy IDs
terraform output policy_ids

# Test SCP in CloudTrail
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ErrorCode,AttributeValue=AccessDenied \
  --max-results 20
```

### Billing Alerts Module
```bash
cd bootstrap/billing-alerts

# Get SNS topic ARN
terraform output sns_topic_arn

# Test notification
aws sns publish \
  --topic-arn $(terraform output -raw sns_topic_arn) \
  --subject "Test Alert" \
  --message "This is a test"

# List budgets
aws budgets describe-budgets \
  --account-id $(aws sts get-caller-identity --query Account --output text)

# Get budget status
terraform output budget_configuration
```

## Advanced Commands

### Taint and Replace
```bash
# Mark resource for recreation
terraform taint aws_cloudwatch_metric_alarm.daily_spend

# Remove taint
terraform untaint aws_cloudwatch_metric_alarm.daily_spend

# Replace resource (Terraform 0.15.2+)
terraform apply -replace="aws_sns_topic.billing_alerts"
```

### Parallel Operations
```bash
# Limit parallel operations (default: 10)
terraform apply -parallelism=2

# Useful for rate-limited APIs or debugging
```

### Variables
```bash
# Pass variable via command line
terraform apply -var="region=us-west-2"

# Pass multiple variables
terraform apply \
  -var="region=us-west-2" \
  -var="monthly_budget_limit=5000" \
  -var="enable_anomaly_detection=true"

# Use variable file
terraform apply -var-file="production.tfvars"

# Use multiple variable files
terraform apply \
  -var-file="common.tfvars" \
  -var-file="production.tfvars"

# Environment variables (must start with TF_VAR_)
export TF_VAR_region="us-west-2"
export TF_VAR_monthly_budget_limit=5000
terraform apply
```

### JSON Output
```bash
# Plan in JSON
terraform plan -json > plan.json

# Show state in JSON
terraform show -json > state.json

# Outputs in JSON
terraform output -json > outputs.json

# Useful for CI/CD pipelines and automation
```

## CI/CD Pipeline Commands

### Non-Interactive Mode
```bash
# Initialize without input
terraform init -input=false

# Plan without input
terraform plan -input=false -out=tfplan

# Apply without input
terraform apply -input=false tfplan

# Full pipeline
terraform init -input=false
terraform validate
terraform plan -input=false -out=tfplan
terraform apply -input=false tfplan
```

### Backend Configuration
```bash
# Configure backend via CLI
terraform init \
  -backend-config="bucket=my-state-bucket" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="region=us-west-2" \
  -backend-config="dynamodb_table=terraform-locks"
```

## Useful Aliases

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Terraform aliases
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfo='terraform output'
alias tfs='terraform state'
alias tfsl='terraform state list'
alias tfss='terraform state show'
alias tfv='terraform validate'
alias tff='terraform fmt -recursive'

# Combined commands
alias tfpa='terraform plan && terraform apply'
alias tfaa='terraform apply -auto-approve'
alias tfda='terraform destroy -auto-approve'

# With common options
alias tfpr='terraform plan -refresh=true'
alias tfar='terraform apply -refresh=true'
```

## Quick Reference Card

```
COMMAND                         DESCRIPTION
========================================================================
terraform init                  Initialize working directory
terraform plan                  Show execution plan
terraform apply                 Apply changes
terraform destroy               Destroy all resources
terraform validate              Validate configuration
terraform fmt                   Format configuration files
terraform output                Show outputs
terraform state list            List resources in state
terraform state show <resource> Show specific resource
terraform refresh               Refresh state
terraform import <addr> <id>    Import existing resource
terraform taint <resource>      Mark for recreation
terraform workspace list        List workspaces
terraform graph                 Generate dependency graph
terraform version               Show version
terraform -help                 Show help
```

## Pro Tips

### Speed up apply with caching
```bash
# Use terraform-plugin-cache directory
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
mkdir -p $TF_PLUGIN_CACHE_DIR
```

### Auto-complete
```bash
# Enable auto-complete (bash)
terraform -install-autocomplete

# Enable auto-complete (zsh)
echo 'autoload -U +X bashcompinit && bashcompinit' >> ~/.zshrc
echo 'complete -o nospace -C /usr/local/bin/terraform terraform' >> ~/.zshrc
```

### Check for updates
```bash
# Check for new provider versions
terraform init -upgrade

# Preview upgrade changes
terraform plan -refresh-only
```

### Safe operations
```bash
# Always review plan before apply
terraform plan -out=tfplan
# Review tfplan
terraform show tfplan
# Apply only if satisfied
terraform apply tfplan
```

## Emergency Procedures

### Locked State
```bash
# Check lock table
aws dynamodb scan --table-name terraform-state-locks

# Get lock info
aws dynamodb get-item \
  --table-name terraform-state-locks \
  --key '{"LockID":{"S":"<bucket-name>/<key>"}}'

# Force unlock (dangerous!)
terraform force-unlock <LOCK_ID>
```

### Corrupted State
```bash
# Backup current state
terraform state pull > state.backup

# Download from S3 directly
aws s3 cp s3://bucket/path/terraform.tfstate ./terraform.tfstate.backup

# Restore from backup
terraform state push terraform.tfstate.backup
```

### Roll Back Changes
```bash
# Download previous state version from S3
aws s3api list-object-versions \
  --bucket my-state-bucket \
  --prefix path/to/terraform.tfstate

# Download specific version
aws s3api get-object \
  --bucket my-state-bucket \
  --key path/to/terraform.tfstate \
  --version-id <version-id> \
  terraform.tfstate.rollback

# Push old state (careful!)
terraform state push terraform.tfstate.rollback
```

## Summary

This reference covers the most common Terraform commands for managing your AWS bootstrap infrastructure. Bookmark this page for quick access during deployments and troubleshooting!
