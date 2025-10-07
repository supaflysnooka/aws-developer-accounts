# Testing Strategy for aws-developer-accounts

## Testing Approach

### Phase 1: Unit Testing (Individual Modules)
**Goal**: Verify each module works independently  
**Timeline**: 2-3 days

### Phase 2: Integration Testing (Module Combinations)
**Goal**: Verify modules work together in realistic patterns  
**Timeline**: 2-3 days

### Phase 3: End-to-End Testing (Complete Scenarios)
**Goal**: Simulate real developer workflows  
**Timeline**: 2 days

### Phase 4: Chaos Testing (Break Things)
**Goal**: Test budget limits, security boundaries, failure scenarios  
**Timeline**: 1-2 days

---

## Phase 1: Unit Testing Individual Modules

### Test Environment Setup
```bash
# Create a test AWS account or use a sandbox
export AWS_PROFILE=test-account
export TF_VAR_environment=test

# Create test directory
mkdir -p tests/unit
cd tests/unit
```

### Module-by-Module Tests

#### 1. **Account Factory Module**
```hcl
# tests/unit/account-factory/main.tf
module "test_account" {
  source = "../../../modules/account-factory"
  
  developer_name    = "test-user"
  developer_email   = "test@boseprofessional.com"
  budget_limit      = 100
  jira_ticket_id   = "TEST-001"
  management_account_id = data.aws_caller_identity.current.account_id
  
  providers = {
    aws                = aws
    aws.target_account = aws.test_account
  }
}
```

**Test Checklist:**
- [ ] Account created successfully
- [ ] S3 state bucket created with versioning
- [ ] DynamoDB lock table created
- [ ] Budget set to $100 with alerts at 80%
- [ ] IAM permission boundary applied
- [ ] VPC created with subnets
- [ ] Onboarding doc generated
- [ ] Backend config file created

**Validation Commands:**
```bash
# Initialize and apply
terraform init
terraform plan
terraform apply -auto-approve

# Verify outputs
terraform output -json > test-results.json

# Check account exists
aws organizations list-accounts | jq '.Accounts[] | select(.Name=="boseprofessional-dev-test-user")'

# Check budget
aws budgets describe-budgets --account-id <ACCOUNT_ID>

# Check state bucket
aws s3 ls | grep boseprofessional-dev-test-user-terraform-state

# Clean up
terraform destroy -auto-approve
```

#### 2. **VPC Module**
```hcl
# tests/unit/vpc/main.tf
module "test_vpc" {
  source = "../../../modules/networking/vpc"
  
  vpc_name           = "test-vpc"
  vpc_cidr          = "10.100.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  
  enable_public_subnets   = true
  enable_private_subnets  = true
  enable_database_subnets = true
  enable_nat_gateway      = true
  single_nat_gateway      = true
  enable_flow_logs        = true
}
```

**Test Checklist:**
- [ ] VPC created with correct CIDR
- [ ] Public subnets created (2)
- [ ] Private subnets created (2)
- [ ] Database subnets created (2)
- [ ] Internet Gateway attached
- [ ] NAT Gateway created
- [ ] Route tables configured correctly
- [ ] VPC Flow Logs enabled
- [ ] Subnet CIDR calculations correct

**Validation Commands:**
```bash
terraform apply -auto-approve

# Verify VPC
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=test-vpc"

# Count subnets
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" | jq '.Subnets | length'

# Check NAT Gateway
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

terraform destroy -auto-approve
```

#### 3. **Security Groups Module**
```hcl
# tests/unit/security-groups/main.tf
module "test_sg" {
  source = "../../../modules/networking/security-groups"
  
  name_prefix = "test"
  vpc_id      = module.test_vpc.vpc_id
  
  create_web_alb_sg     = true
  create_web_backend_sg = true
  create_database_sg    = true
  create_lambda_sg      = true
}
```

**Test Checklist:**
- [ ] All security groups created
- [ ] ALB allows 80/443 from 0.0.0.0/0
- [ ] Backend allows traffic from ALB only
- [ ] Database allows 5432 from backend only
- [ ] Lambda has outbound internet access
- [ ] No overly permissive rules

#### 4. **ALB Module**
```hcl
module "test_alb" {
  source = "../../../modules/networking/alb"
  
  alb_name           = "test-alb"
  vpc_id             = module.test_vpc.vpc_id
  subnet_ids         = module.test_vpc.public_subnets
  security_group_ids = [module.test_sg.web_alb_security_group_id]
  
  create_http_listener    = true
  http_redirect_to_https  = false  # For testing
}
```

**Test Checklist:**
- [ ] ALB created in public subnets
- [ ] HTTP listener created
- [ ] Default target group created
- [ ] Health checks configured
- [ ] DNS name accessible

**Validation:**
```bash
# Get ALB DNS
ALB_DNS=$(terraform output -raw load_balancer_dns_name)

# Test HTTP endpoint (should return 503 with no targets)
curl -I http://$ALB_DNS

# Check target group health
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw default_target_group_arn)
```

#### 5. **ECS Service Module**
```hcl
module "test_ecs" {
  source = "../../../modules/containers/ecs-service"
  
  cluster_name    = "test-cluster"
  service_name    = "test-service"
  container_image = "nginx:latest"
  container_port  = 80
  
  vpc_id     = module.test_vpc.vpc_id
  subnet_ids = module.test_vpc.private_subnets
  
  target_group_arn = module.test_alb.default_target_group_arn
  
  desired_count      = 1
  enable_autoscaling = false
}
```

**Test Checklist:**
- [ ] ECS cluster created
- [ ] Task definition registered
- [ ] Service running with desired count
- [ ] Tasks healthy in target group
- [ ] CloudWatch logs streaming
- [ ] Can access via ALB

**Validation:**
```bash
# Check service status
aws ecs describe-services --cluster test-cluster --services test-service

# Check running tasks
aws ecs list-tasks --cluster test-cluster --service-name test-service

# Wait for healthy targets
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw default_target_group_arn)

# Test via ALB (should get nginx default page)
curl http://$ALB_DNS
```

#### 6. **ECR Module**
```hcl
module "test_ecr" {
  source = "../../../modules/containers/ecr"
  
  repository_name = "test-app"
  scan_on_push    = true
  
  enable_lifecycle_policy         = true
  untagged_image_retention_count  = 3
  tagged_image_retention_count    = 10
}
```

**Test Checklist:**
- [ ] Repository created
- [ ] Scan on push enabled
- [ ] Lifecycle policy applied
- [ ] Can push image
- [ ] Image scan completes

**Validation:**
```bash
# Get repository URL
REPO_URL=$(terraform output -raw repository_url)

# Login to ECR
aws ecr get-login-password | docker login --username AWS --password-stdin $REPO_URL

# Push test image
docker pull nginx:latest
docker tag nginx:latest $REPO_URL:test
docker push $REPO_URL:test

# Check image scan results
aws ecr describe-image-scan-findings --repository-name test-app --image-id imageTag=test
```

#### 7. **RDS Module**
```hcl
module "test_rds" {
  source = "../../../modules/databases/rds"
  
  db_name     = "testdb"
  db_username = "admin"
  
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.micro"
  
  allocated_storage = 20
  
  subnet_ids             = module.test_vpc.database_subnets
  vpc_security_group_ids = [module.test_sg.database_security_group_id]
  
  manage_master_user_password = true
  skip_final_snapshot        = true
}
```

**Test Checklist:**
- [ ] RDS instance created
- [ ] Password stored in Secrets Manager
- [ ] In database subnet group
- [ ] Security group allows access
- [ ] Backups enabled
- [ ] Monitoring enabled
- [ ] Can connect from app

**Validation:**
```bash
# Wait for availability
aws rds wait db-instance-available --db-instance-identifier testdb

# Get endpoint
ENDPOINT=$(terraform output -raw db_endpoint)

# Get password from Secrets Manager
SECRET_ARN=$(terraform output -raw secret_arn)
PASSWORD=$(aws secretsmanager get-secret-value --secret-id $SECRET_ARN --query SecretString --output text | jq -r .password)

# Test connection (from a bastion or ECS task)
psql -h $ENDPOINT -U admin -d testdb
```

#### 8. **S3 Module**
```hcl
module "test_s3" {
  source = "../../../modules/storage/s3"
  
  bucket_name       = "boseprofessional-test-bucket-${random_id.bucket.hex}"
  enable_versioning = true
  
  lifecycle_rules = [{
    id      = "cleanup"
    enabled = true
    filter  = { prefix = "tmp/" }
    expiration_days = 7
  }]
}
```

**Test Checklist:**
- [ ] Bucket created
- [ ] Versioning enabled
- [ ] Encryption enabled
- [ ] Public access blocked
- [ ] Lifecycle rules applied
- [ ] Can upload/download objects

#### 9. **API Gateway Module**
```hcl
module "test_api" {
  source = "../../../modules/api/api-gateway"
  
  api_name  = "test-api"
  api_type  = "http"
  
  enable_cors = true
  cors_allow_origins = ["*"]
}
```

**Test Checklist:**
- [ ] API created
- [ ] Stage deployed
- [ ] CORS configured
- [ ] Endpoint accessible
- [ ] Logs enabled

#### 10. **Secrets Manager Module**
```hcl
module "test_secret" {
  source = "../../../modules/security/secrets-manager"
  
  secret_name            = "test-secret"
  generate_secret_string = true
  username               = "testuser"
}
```

**Test Checklist:**
- [ ] Secret created
- [ ] Password generated
- [ ] Can retrieve secret
- [ ] Encryption enabled

---

## Phase 2: Integration Testing

### Test Scenario 1: Web Application Stack
**Components**: VPC + Security Groups + ALB + ECS + RDS + Secrets

```hcl
# tests/integration/web-app/main.tf
# Full stack deployment
```

**Test Flow:**
1. Deploy all infrastructure
2. Deploy sample app to ECS
3. Verify app can connect to database
4. Access app through ALB
5. Check logs and metrics
6. Verify auto-scaling works
7. Test database failover

### Test Scenario 2: Serverless API
**Components**: VPC + API Gateway + Lambda (placeholder) + DynamoDB (placeholder)

### Test Scenario 3: Container CI/CD Pipeline
**Components**: ECR + ECS + ALB with blue/green deployment

---

## Phase 3: End-to-End Testing

### Developer Workflow Simulation

#### Test Case 1: New Developer Onboarding
```bash
#!/bin/bash
# tests/e2e/developer-onboarding.sh

# 1. Request account (simulate)
echo "Creating developer account..."
cd environments/dev-accounts
terraform apply -var="developer_name=test-developer"

# 2. Wait for provisioning
sleep 60

# 3. Configure AWS CLI
ACCOUNT_ID=$(terraform output -json | jq -r '.john_smith.account_id')
aws configure set profile.test-dev role_arn arn:aws:iam::${ACCOUNT_ID}:role/DeveloperRole

# 4. Test access
aws sts get-caller-identity --profile test-dev

# 5. Deploy sample application
cd ../../templates/application-patterns/web-application
terraform init -backend-config="profile=test-dev"
terraform apply -auto-approve

# 6. Verify application is running
APP_URL=$(terraform output -raw application_url)
curl -I http://$APP_URL

# 7. Check cost tracking
aws ce get-cost-and-usage --time-period Start=2024-10-01,End=2024-10-31 --granularity MONTHLY --metrics UnblendedCost --profile test-dev

echo "Developer onboarding test complete"
```

#### Test Case 2: Budget Enforcement
```bash
#!/bin/bash
# tests/e2e/budget-enforcement.sh

# 1. Deploy expensive resources
terraform apply -var="instance_type=t3.large" -var="instance_count=20"

# 2. Monitor budget
while true; do
    SPEND=$(aws ce get-cost-and-usage --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) --granularity MONTHLY --metrics UnblendedCost --profile test-dev | jq -r '.ResultsByTime[0].Total.UnblendedCost.Amount')
    echo "Current spend: \$$SPEND"
    
    if (( $(echo "$SPEND > 90" | bc -l) )); then
        echo "Budget alert triggered at $SPEND"
    fi
    
    if (( $(echo "$SPEND >= 100" | bc -l) )); then
        echo "Budget limit REACHED - checking for automatic termination"
        break
    fi
    
    sleep 300
done

# 3. Verify resources were terminated
RUNNING_INSTANCES=$(aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --profile test-dev | jq '.Reservations | length')
echo "Running instances after budget limit: $RUNNING_INSTANCES"

[ "$RUNNING_INSTANCES" -eq "0" ] && echo "Budget enforcement working" || echo "Budget enforcement failed"
```

#### Test Case 3: Security Boundary Testing
```bash
#!/bin/bash
# tests/e2e/security-boundaries.sh

echo "Testing security boundaries..."

# 1. Try to access billing (should fail)
aws ce get-cost-and-usage --profile test-dev 2>&1 | grep -q "AccessDenied" && echo "Billing access blocked" || echo "Billing access not blocked"

# 2. Try to access AWS Marketplace (should fail)
aws marketplace-catalog list-entities --profile test-dev 2>&1 | grep -q "AccessDenied" && echo "Marketplace access blocked" || echo "Marketplace access not blocked"

# 3. Try to create expensive instance (should fail)
aws ec2 run-instances --instance-type m5.4xlarge --image-id ami-12345 --profile test-dev 2>&1 | grep -q "not authorized" && echo "Expensive instance blocked" || echo "Expensive instance not blocked"

# 4. Try to create allowed instance (should succeed)
aws ec2 run-instances --instance-type t3.micro --image-id ami-12345 --profile test-dev && echo "Allowed instance type works" || echo "Allowed instance type blocked incorrectly"

# 5. Try to modify IAM without boundary (should fail)
aws iam create-role --role-name test-role --profile test-dev 2>&1 | grep -q "permission boundary" && echo "IAM boundary enforced" || echo "IAM boundary not enforced"

echo "Security boundary testing complete"
```

---

## Phase 4: Chaos Testing

### Chaos Test 1: Failure Scenarios
```bash
# Kill random ECS tasks
aws ecs stop-task --cluster test-cluster --task $(aws ecs list-tasks --cluster test-cluster --query 'taskArns[0]' --output text)

# Verify auto-recovery
sleep 30
RUNNING_TASKS=$(aws ecs list-tasks --cluster test-cluster --desired-status RUNNING | jq '.taskArns | length')
[ "$RUNNING_TASKS" -gt "0" ] && echo "Auto-recovery works"
```

### Chaos Test 2: Network Failures
```bash
# Remove NAT Gateway temporarily
aws ec2 delete-nat-gateway --nat-gateway-id <NAT_GW_ID>

# Verify private subnet instances can't reach internet
# Verify database connections still work internally

# Restore NAT Gateway
terraform apply -auto-approve
```

### Chaos Test 3: Database Failover
```bash
# Force RDS failover
aws rds reboot-db-instance --db-instance-identifier testdb --force-failover

# Verify application continues to work
curl -I http://$APP_URL
```

---

## Automated Test Suite

### Create Test Framework
```bash
# tests/run-all-tests.sh
#!/bin/bash

set -e

echo "🧪 Starting Terraform Module Test Suite"
echo "========================================"

# Phase 1: Unit Tests
echo "Phase 1: Unit Testing"
for module in account-factory vpc security-groups alb ecs ecr rds s3 api-gateway secrets-manager; do
    echo "Testing $module..."
    cd tests/unit/$module
    terraform init
    terraform validate
    terraform plan
    cd -
done

# Phase 2: Integration Tests
echo "Phase 2: Integration Testing"
./tests/integration/web-app/test.sh
./tests/integration/serverless-api/test.sh

# Phase 3: E2E Tests
echo "Phase 3: End-to-End Testing"
./tests/e2e/developer-onboarding.sh
./tests/e2e/budget-enforcement.sh
./tests/e2e/security-boundaries.sh

# Phase 4: Chaos Tests
echo "Phase 4: Chaos Testing"
./tests/chaos/failure-scenarios.sh

echo "All tests completed successfully!"
```

---

## Test Metrics & Success Criteria

### Passing Criteria
- [ ] **100%** of unit tests pass
- [ ] **100%** of security boundary tests pass
- [ ] **95%+** of integration tests pass
- [ ] Budget enforcement triggers correctly
- [ ] No unauthorized access possible
- [ ] All modules deploy in < 15 minutes
- [ ] Zero security vulnerabilities in container scans
- [ ] All CloudWatch alarms functioning
- [ ] Logs captured for all services

### Performance Benchmarks
- Account provisioning: < 10 minutes
- VPC creation: < 5 minutes
- ECS service deployment: < 5 minutes
- RDS provisioning: < 15 minutes
- Application deployment end-to-end: < 30 minutes

---

## Test Reporting

### Create Test Report Template
```markdown
# Test Execution Report
**Date**: 2024-09-XX
**Tester**: [Name]
**Environment**: Test Account

## Summary
- Total Tests: X
- Passed: Y
- Failed: Z
- Skipped: W

## Detailed Results

### Unit Tests
| Module | Status | Duration | Notes |
|--------|--------|----------|-------|
| account-factory | ✅ | 8m | All checks passed |
| vpc | ✅ | 4m | CIDR calculations correct |
...

### Issues Found
1. **Issue**: [Description]
   - **Severity**: High/Medium/Low
   - **Module**: [Module name]
   - **Fix**: [Resolution]

### Recommendations
- [Action item 1]
- [Action item 2]
```

---

## Quick Start Testing

### Minimal Test (30 minutes)
```bash
# Test just the critical path
cd tests/quick
terraform init
terraform apply -auto-approve

# Verify VPC + ALB + ECS works
curl http://$(terraform output -raw alb_dns_name)

terraform destroy -auto-approve
```

### Full Test Suite (4-6 hours)
```bash
# Run complete validation
./tests/run-all-tests.sh
```

This testing strategy ensures your October 3rd delivery is solid!
