# ECS Service Module

Creates an Amazon ECS (Elastic Container Service) Fargate service with automatic scaling, load balancer integration, and CloudWatch monitoring.

## Features

- **Fargate Launch Type**: Serverless containers (no EC2 management)
- **Auto-scaling**: CPU and memory-based scaling policies
- **Load Balancer Integration**: Direct integration with ALB/NLB
- **Service Discovery**: AWS Cloud Map integration
- **Secrets Management**: Secure environment variable injection
- **Container Insights**: CloudWatch monitoring and dashboards
- **Health Checks**: Configurable container health monitoring
- **Rolling Deployments**: Zero-downtime updates

## Usage

### Basic Example

```hcl
module "ecs_service" {
  source = "../../modules/containers/ecs-service"
  
  cluster_name    = "my-cluster"
  service_name    = "web-app"
  container_image = "nginx:latest"
  container_port  = 80
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  target_group_arn = module.alb.default_target_group_arn
}
```

### Complete Production Example

```hcl
module "ecs_service" {
  source = "../../modules/containers/ecs-service"
  
  # Service Configuration
  cluster_name   = "production-cluster"
  service_name   = "api-service"
  container_name = "api"
  container_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-api:v1.2.3"
  container_port = 3000
  
  # Resources
  task_cpu    = 512   # 0.5 vCPU
  task_memory = 1024  # 1 GB
  
  # Networking
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  # Load Balancer
  target_group_arn = module.alb.default_target_group_arn
  
  # Auto-scaling
  enable_autoscaling = true
  min_capacity      = 2
  max_capacity      = 10
  cpu_target_value  = 70
  
  # Environment Variables
  environment_variables = {
    NODE_ENV    = "production"
    API_VERSION = "v1"
    LOG_LEVEL   = "info"
  }
  
  # Secrets from Secrets Manager
  secrets = {
    DATABASE_URL = module.database_secret.secret_arn
    API_KEY      = module.api_secret.secret_arn
  }
  
  # Health Check
  health_check_command = ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]
  health_check_interval = 30
  health_check_timeout  = 5
  health_check_retries  = 3
  
  # Monitoring
  enable_container_insights = true
  log_retention_days       = 30
  
  tags = {
    Environment = "production"
    Service     = "api"
  }
}
```

### With Service Discovery

```hcl
# Create service discovery namespace
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "internal.local"
  vpc         = module.vpc.vpc_id
  description = "Private DNS namespace for ECS services"
}

# Create service discovery service
resource "aws_service_discovery_service" "api" {
  name = "api"
  
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
  
  health_check_custom_config {
    failure_threshold = 1
  }
}

# ECS Service with Service Discovery
module "ecs_service" {
  source = "../../modules/containers/ecs-service"
  
  cluster_name    = "my-cluster"
  service_name    = "api"
  container_image = "my-api:latest"
  container_port  = 3000
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  # Service Discovery
  service_discovery_registry_arn = aws_service_discovery_service.api.arn
  
  # No load balancer needed for internal services
  target_group_arn = null
}

# Other services can now connect via DNS: api.internal.local:3000
```

## Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `cluster_name` | string | Name of the ECS cluster |
| `service_name` | string | Name of the ECS service |
| `container_image` | string | Docker image to run (e.g., nginx:latest) |
| `vpc_id` | string | VPC ID |
| `subnet_ids` | list(string) | Subnet IDs for task placement |

### Container Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `container_name` | string | null (uses service_name) | Name of the container |
| `container_port` | number | null | Port container listens on |
| `task_cpu` | number | 256 | Task CPU units (256 = 0.25 vCPU) |
| `task_memory` | number | 512 | Task memory in MB |
| `desired_count` | number | 1 | Number of tasks to run |

**Valid CPU/Memory Combinations**:
| CPU (vCPU) | Memory Options (GB) |
|------------|---------------------|
| 256 (.25)  | 0.5, 1, 2 |
| 512 (.5)   | 1, 2, 3, 4 |
| 1024 (1)   | 2, 3, 4, 5, 6, 7, 8 |
| 2048 (2)   | 4-16 (1 GB increments) |
| 4096 (4)   | 8-30 (1 GB increments) |

### Environment & Secrets

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `environment_variables` | map(string) | {} | Environment variables (plaintext) |
| `secrets` | map(string) | {} | Secrets from Secrets Manager/SSM (key → ARN) |

### Networking

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `assign_public_ip` | bool | false | Assign public IP to tasks |
| `target_group_arn` | string | null | ALB/NLB target group ARN |
| `service_discovery_registry_arn` | string | null | Service discovery registry ARN |
| `ingress_rules` | list(object) | [] | Custom security group ingress rules |
| `allow_container_port_ingress` | bool | false | Allow inbound on container port |
| `allowed_cidr_blocks` | list(string) | ["10.0.0.0/8"] | CIDR blocks for container port access |

### Health Checks

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `health_check_command` | list(string) | null | Health check command |
| `health_check_interval` | number | 30 | Interval in seconds |
| `health_check_timeout` | number | 5 | Timeout in seconds |
| `health_check_retries` | number | 3 | Number of retries |
| `health_check_start_period` | number | 60 | Grace period in seconds |

**Health Check Command Examples**:
```hcl
# HTTP health check
health_check_command = ["CMD-SHELL", "curl -f http://localhost/health || exit 1"]

# TCP health check
health_check_command = ["CMD-SHELL", "nc -z localhost 3000 || exit 1"]

# Custom script
health_check_command = ["CMD-SHELL", "/app/healthcheck.sh"]
```

### Auto-scaling

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_autoscaling` | bool | false | Enable auto-scaling |
| `min_capacity` | number | 1 | Minimum task count |
| `max_capacity` | number | 10 | Maximum task count |
| `cpu_target_value` | number | 70 | Target CPU % for scaling |
| `memory_target_value` | number | 80 | Target memory % for scaling |

### Monitoring

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_container_insights` | bool | true | Enable CloudWatch Container Insights |
| `log_retention_days` | number | 30 | CloudWatch log retention |
| `platform_version` | string | "LATEST" | Fargate platform version |

### IAM

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `task_role_arn` | string | null | Custom task role ARN (module creates one if null) |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `cluster_id` | string | ECS cluster ID |
| `cluster_arn` | string | ECS cluster ARN |
| `service_id` | string | ECS service ID |
| `service_arn` | string | ECS service ARN |
| `task_definition_arn` | string | Task definition ARN |
| `security_group_id` | string | Service security group ID |
| `execution_role_arn` | string | ECS execution role ARN |
| `task_role_arn` | string | ECS task role ARN |
| `log_group_name` | string | CloudWatch log group name |

## Cost Considerations

**Fargate Pricing** (as of 2024):
- **vCPU**: ~$0.04048/hour per vCPU
- **Memory**: ~$0.004445/hour per GB

**Monthly Cost Examples**:
```
Task: 0.25 vCPU, 0.5 GB memory
- 1 task:  ~$7/month
- 2 tasks: ~$14/month
- 5 tasks: ~$35/month

Task: 0.5 vCPU, 1 GB memory
- 1 task:  ~$14/month
- 2 tasks: ~$28/month
- 5 tasks: ~$70/month

Task: 1 vCPU, 2 GB memory  
- 1 task:  ~$30/month
- 2 tasks: ~$60/month
- 5 tasks: ~$150/month
```

**Additional Costs**:
- **NAT Gateway**: $32.85/month + data transfer ($0.045/GB)
- **Load Balancer**: $16.20/month + LCU charges
- **CloudWatch Logs**: $0.50/GB ingested
- **ECR**: $0.10/GB/month for storage

**Cost Optimization**:
1. Right-size CPU/memory (monitor actual usage)
2. Use Fargate Spot for non-critical workloads (70% discount)
3. Implement aggressive auto-scaling policies
4. Set appropriate log retention (7-30 days vs 365 days)
5. Use CloudWatch log filtering to reduce ingestion

## Common Patterns

### Pattern 1: Web Application with Database

```hcl
module "web_service" {
  source = "../../modules/containers/ecs-service"
  
  cluster_name    = "web-cluster"
  service_name    = "frontend"
  container_image = "my-web-app:latest"
  container_port  = 80
  
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets
  target_group_arn   = module.alb.default_target_group_arn
  
  # Connect to RDS
  secrets = {
    DATABASE_URL = module.database.secret_arn
  }
  
  environment_variables = {
    REDIS_HOST = aws_elasticache_cluster.redis.cache_nodes[0].address
  }
  
  enable_autoscaling = true
  min_capacity      = 2
  max_capacity      = 10
}
```

### Pattern 2: Background Worker

```hcl
module "worker_service" {
  source = "../../modules/containers/ecs-service"
  
  cluster_name    = "worker-cluster"
  service_name    = "queue-processor"
  container_image = "my-worker:latest"
  
  # No port - doesn't accept incoming connections
  container_port = null
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  # No load balancer
  target_group_arn = null
  
  # Process SQS messages
  environment_variables = {
    SQS_QUEUE_URL = aws_sqs_queue.tasks.url
  }
  
  # Scale based on queue depth
  enable_autoscaling = true
  min_capacity      = 1
  max_capacity      = 20
}

# Custom scaling based on SQS queue
resource "aws_appautoscaling_policy" "queue_depth" {
  name               = "queue-depth-scaling"
  service_namespace  = "ecs"
  resource_id        = "service/${module.worker_service.cluster_id}/${module.worker_service.service_id}"
  scalable_dimension = "ecs:service:DesiredCount"
  
  target_tracking_scaling_policy_configuration {
    customized_metric_specification {
      metric_name = "ApproximateNumberOfMessagesVisible"
      namespace   = "AWS/SQS"
      statistic   = "Average"
      
      dimensions {
        name  = "QueueName"
        value = aws_sqs_queue.tasks.name
      }
    }
    
    target_value = 100  # 100 messages per task
  }
}
```

### Pattern 3: Microservices with Service Mesh

```hcl
# Service A
module "service_a" {
  source = "../../modules/containers/ecs-service"
  
  cluster_name    = "microservices"
  service_name    = "users-api"
  container_image = "users-api:latest"
  container_port  = 3000
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  service_discovery_registry_arn = aws_service_discovery_service.users.arn
}

# Service B
module "service_b" {
  source = "../../modules/containers/ecs-service"
  
  cluster_name    = "microservices"
  service_name    = "orders-api"
  container_image = "orders-api:latest"
  container_port  = 3001
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  service_discovery_registry_arn = aws_service_discovery_service.orders.arn
  
  # Can call users-api via: http://users-api.internal.local:3000
}
```

### Pattern 4: Scheduled Tasks

```hcl
# ECS cluster for scheduled tasks
module "batch_cluster" {
  source = "../../modules/containers/ecs-service"
  
  cluster_name    = "batch-jobs"
  service_name    = "report-generator"
  container_image = "report-gen:latest"
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  # Run 0 tasks normally
  desired_count = 0
}

# EventBridge rule to run daily
resource "aws_cloudwatch_event_rule" "daily_report" {
  name                = "daily-report-generation"
  schedule_expression = "cron(0 6 * * ? *)"  # 6 AM daily
}

resource "aws_cloudwatch_event_target" "ecs_task" {
  rule      = aws_cloudwatch_event_rule.daily_report.name
  target_id = "RunDailyReport"
  arn       = module.batch_cluster.cluster_arn
  role_arn  = aws_iam_role.ecs_events.arn
  
  ecs_target {
    task_count          = 1
    task_definition_arn = module.batch_cluster.task_definition_arn
    launch_type         = "FARGATE"
    
    network_configuration {
      subnets         = module.vpc.private_subnets
      security_groups = [module.batch_cluster.security_group_id]
    }
  }
}
```

## Troubleshooting

### Issue: Tasks Keep Stopping

**Symptoms**: Tasks start but immediately stop with exit code 1.

**Debugging**:
```bash
# Check task logs
aws logs tail /ecs/my-service --follow

# Check task stopped reason
aws ecs describe-tasks \
  --cluster my-cluster \
  --tasks $(aws ecs list-tasks --cluster my-cluster --service-name my-service --query 'taskArns[0]' --output text)

# Common issues:
# - Application crashes (check logs)
# - Health check failing
# - Out of memory
# - Missing secrets/environment variables
```

**Solutions**:
```hcl
# Increase health check grace period
health_check_start_period = 120  # 2 minutes

# Increase memory
task_memory = 1024  # Was 512

# Fix secrets
secrets = {
  # Make sure ARN is correct and task has permission
  DATABASE_URL = "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-password-abc123"
}
```

### Issue: Tasks Can't Pull Image

**Error**: `CannotPullContainerError: Error response from daemon`

**Solution**:
```bash
# Verify image exists
aws ecr describe-images --repository-name my-app --image-ids imageTag=latest

# Check execution role has ECR permissions (module includes this by default)
aws iam get-role-policy \
  --role-name my-service-ecs-execution-role \
  --policy-name ecr-policy

# If using private registry, add credentials
secrets = {
  DOCKER_USERNAME = aws_secretsmanager_secret.docker_user.arn
  DOCKER_PASSWORD = aws_secretsmanager_secret.docker_pass.arn
}
```

### Issue: Can't Connect to Database

**Symptoms**: Application logs show "Connection refused" or timeout.

**Solution**:
```bash
# Check security groups
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw security_group_id)

# Ensure ECS security group can reach database
# Database SG should allow inbound from ECS SG on port 5432/3306

# Test connectivity from ECS task
aws ecs execute-command \
  --cluster my-cluster \
  --task <TASK_ID> \
  --command "nc -zv database-endpoint.us-east-1.rds.amazonaws.com 5432" \
  --interactive
```

### Issue: High Memory Usage

**Symptoms**: Tasks killed with OOM (out of memory).

**Solution**:
```bash
# Check actual memory usage in Container Insights
aws cloudwatch get-metric-statistics \
  --namespace ECS/ContainerInsights \
  --metric-name MemoryUtilized \
  --dimensions Name=ServiceName,Value=my-service \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 300 \
  --statistics Average

# Increase task memory
task_memory = 2048  # Was 1024

# Or optimize application (check for memory leaks)
```

### Issue: ALB Health Check Failing

**Symptoms**: Targets show as unhealthy in ALB.

**Debugging**:
```bash
# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN>

# Common issues:
# - Health check path returns 404
# - Application not listening on configured port
# - Security group blocking ALB → ECS traffic
```

**Solution**:
```hcl
# In ALB module, adjust health check
health_check_path    = "/health"  # Make sure this endpoint exists
health_check_matcher = "200,204"  # Accept multiple status codes

# In ECS service, ensure security group allows ALB
ingress_rules = [{
  from_port       = 3000
  to_port         = 3000
  protocol        = "tcp"
  security_groups = [module.alb.security_group_id]
  description     = "Allow ALB traffic"
}]
```

## Monitoring

### CloudWatch Metrics

Key metrics to monitor:
- **CPUUtilization**: Keep below 80%
- **MemoryUtilization**: Keep below 80%
- **RunningTaskCount**: Should match desired count
- **TargetResponseTime** (if using ALB): Monitor latency

### Sample Dashboard

```hcl
resource "aws_cloudwatch_dashboard" "ecs" {
  dashboard_name = "ECS-${var.service_name}"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", { stat = "Average" }],
            [".", "MemoryUtilization", { stat = "Average" }]
          ]
          region = "us-east-1"
          title  = "Resource Utilization"
        }
      }
    ]
  })
}
```

### Logs

```bash
# Tail logs
aws logs tail /ecs/my-service --follow --since 5m

# Search logs
aws logs filter-log-events \
  --log-group-name /ecs/my-service \
  --filter-pattern "ERROR"

# Export to S3 for long-term storage
aws logs create-export-task \
  --log-group-name /ecs/my-service \
  --from 1640995200000 \
  --to 1641081600000 \
  --destination s3-bucket-name \
  --destination-prefix ecs-logs/
```

## Integration Examples

### With ALB

```hcl
module "alb" {
  source = "../../modules/networking/alb"
  # ... ALB config
}

module "ecs" {
  source = "../../modules/containers/ecs-service"
  
  target_group_arn = module.alb.default_target_group_arn
  # ... ECS config
}
```

### With RDS

```hcl
module "database" {
  source = "../../modules/databases/rds"
  
  manage_master_user_password = true
  # ... RDS config
}

module "ecs" {
  source = "../../modules/containers/ecs-service"
  
  secrets = {
    DATABASE_URL = module.database.secret_arn
  }
}
```

### With ECR

```hcl
module "ecr" {
  source = "../../modules/containers/ecr"
  
  repository_name = "my-app"
}

module "ecs" {
  source = "../../modules/containers/ecs-service"
  
  container_image = "${module.ecr.repository_url}:latest"
}
```

## Security Best Practices

1. **Use private subnets**: Deploy tasks in private subnets, not public
2. **Least privilege IAM**: Task role should have minimum required permissions
3. **Secrets management**: Never use environment variables for secrets
4. **Image scanning**: Enable ECR image scanning
5. **Read-only root filesystem**: Where possible, use read-only containers
6. **Non-root user**: Run containers as non-root user

```dockerfile
# In your Dockerfile
FROM node:18-alpine
USER node
WORKDIR /app
# ...
```

## References

- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [Fargate Pricing](https://aws.amazon.com/fargate/pricing/)
- [Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
- [ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
