# Application Load Balancer Module

Creates an Application Load Balancer with HTTP/HTTPS listeners, target groups, health checks, and routing rules for distributing traffic across multiple targets.

## Features

- HTTP and HTTPS listeners
- SSL/TLS termination
- Path-based and host-based routing
- Health checks with customizable parameters
- Session stickiness (sticky sessions)
- Multiple target groups
- WAF integration
- CloudWatch alarms
- Route53 integration

## Usage

### Basic HTTP Load Balancer

```hcl
module "alb" {
  source = "../../modules/networking/alb"
  
  alb_name           = "my-app-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnets
  security_group_ids = [module.security_groups.web_alb_security_group_id]
  
  create_http_listener = true
}

output "alb_dns" {
  value = module.alb.load_balancer_dns_name
}
```

### HTTPS Load Balancer with SSL

```hcl
module "alb" {
  source = "../../modules/networking/alb"
  
  alb_name           = "secure-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnets
  security_group_ids = [module.security_groups.web_alb_security_group_id]
  
  # HTTP redirects to HTTPS
  create_http_listener  = true
  http_redirect_to_https = true
  
  # HTTPS listener
  create_https_listener = true
  certificate_arn       = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxx"
  ssl_policy            = "ELBSecurityPolicy-TLS-1-2-2017-01"
  
  # Custom domain
  create_route53_record = true
  route53_zone_id      = "Z1234567890ABC"
  domain_name          = "app.example.com"
}
```

### Multiple Target Groups with Path Routing

```hcl
module "alb" {
  source = "../../modules/networking/alb"
  
  alb_name           = "microservices-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnets
  security_group_ids = [module.security_groups.web_alb_security_group_id]
  
  # Default target group
  default_target_group_port = 8080
  
  # Additional target groups
  additional_target_groups = {
    api = {
      port     = 3000
      protocol = "HTTP"
      target_type = "ip"
      health_check = {
        enabled             = true
        healthy_threshold   = 2
        unhealthy_threshold = 2
        timeout             = 5
        interval            = 30
        path                = "/api/health"
        matcher             = "200"
        port                = "traffic-port"
        protocol            = "HTTP"
      }
      enable_stickiness         = false
      deregistration_delay     = 30
      tags = {}
    }
    admin = {
      port     = 8081
      protocol = "HTTP"
      target_type = "ip"
      health_check = {
        enabled             = true
        healthy_threshold   = 2
        unhealthy_threshold = 2
        timeout             = 5
        interval            = 30
        path                = "/health"
        matcher             = "200"
        port                = "traffic-port"
        protocol            = "HTTP"
      }
      enable_stickiness         = true
      stickiness_type          = "lb_cookie"
      stickiness_cookie_duration = 86400
      deregistration_delay     = 60
      tags = {}
    }
  }
  
  # Routing rules
  listener_rules = {
    api_route = {
      listener_type = "https"
      priority      = 100
      action_type   = "forward"
      target_group_key = "api"
      target_group_weight = 100
      path_pattern  = "/api/*"
      tags = {}
    }
    admin_route = {
      listener_type = "https"
      priority      = 200
      action_type   = "forward"
      target_group_key = "admin"
      target_group_weight = 100
      path_pattern  = "/admin/*"
      tags = {}
    }
  }
  
  create_https_listener = true
  certificate_arn       = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxx"
}
```

## Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `alb_name` | string | Name of the load balancer |
| `vpc_id` | string | VPC ID |
| `subnet_ids` | list(string) | Public subnet IDs (minimum 2 AZs) |
| `security_group_ids` | list(string) | Security group IDs |

### Load Balancer Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `internal` | bool | false | Create internal load balancer |
| `enable_deletion_protection` | bool | false | Enable deletion protection |
| `enable_cross_zone_load_balancing` | bool | true | Enable cross-zone load balancing |
| `enable_http2` | bool | true | Enable HTTP/2 |
| `enable_waf_fail_open` | bool | false | Enable WAF fail open |

### Access Logs

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_access_logs` | bool | false | Enable access logs to S3 |
| `access_logs_bucket` | string | "" | S3 bucket for logs |
| `access_logs_prefix` | string | "" | S3 prefix for logs |

### Default Target Group

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `default_target_group_port` | number | 80 | Default target group port |
| `default_target_group_protocol` | string | "HTTP" | Default protocol |
| `target_type` | string | "ip" | Target type (ip, instance, lambda) |

### Health Checks

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `health_check_enabled` | bool | true | Enable health checks |
| `health_check_healthy_threshold` | number | 2 | Consecutive successes required |
| `health_check_unhealthy_threshold` | number | 2 | Consecutive failures required |
| `health_check_timeout` | number | 5 | Timeout in seconds |
| `health_check_interval` | number | 30 | Interval in seconds |
| `health_check_path` | string | "/" | Health check path |
| `health_check_matcher` | string | "200" | Success HTTP codes |
| `health_check_port` | string | "traffic-port" | Health check port |
| `health_check_protocol` | string | "HTTP" | Health check protocol |

### Stickiness

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_stickiness` | bool | false | Enable session stickiness |
| `stickiness_type` | string | "lb_cookie" | Stickiness type |
| `stickiness_cookie_duration` | number | 86400 | Cookie duration in seconds (1 day) |
| `deregistration_delay` | number | 300 | Deregistration delay in seconds |

### Listeners

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_http_listener` | bool | true | Create HTTP listener |
| `http_redirect_to_https` | bool | true | Redirect HTTP to HTTPS |
| `create_https_listener` | bool | false | Create HTTPS listener |
| `certificate_arn` | string | "" | ACM certificate ARN |
| `ssl_policy` | string | "ELBSecurityPolicy-TLS-1-2-2017-01" | SSL security policy |
| `additional_certificate_arns` | set(string) | [] | Additional certificates for SNI |

### Routing

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `listener_rules` | map(object) | {} | Listener routing rules |
| `additional_target_groups` | map(object) | {} | Additional target groups |

### Route53

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_route53_record` | bool | false | Create Route53 alias record |
| `route53_zone_id` | string | "" | Route53 hosted zone ID |
| `domain_name` | string | "" | Domain name for alias |
| `route53_evaluate_target_health` | bool | true | Evaluate target health |

### WAF

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `web_acl_arn` | string | null | WAF WebACL ARN |

### Monitoring

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_cloudwatch_alarms` | bool | false | Create CloudWatch alarms |
| `target_response_time_threshold` | number | 1.0 | Response time threshold (seconds) |
| `http_5xx_threshold` | number | 10 | 5XX error count threshold |
| `alarm_actions` | list(string) | [] | SNS topic ARNs for alarms |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `load_balancer_id` | string | Load balancer ID |
| `load_balancer_arn` | string | Load balancer ARN |
| `load_balancer_arn_suffix` | string | Load balancer ARN suffix (for CloudWatch) |
| `load_balancer_dns_name` | string | Load balancer DNS name |
| `load_balancer_zone_id` | string | Load balancer hosted zone ID |
| `default_target_group_arn` | string | Default target group ARN |
| `default_target_group_arn_suffix` | string | Default target group ARN suffix |
| `additional_target_group_arns` | map(string) | Additional target group ARNs |
| `http_listener_arn` | string | HTTP listener ARN |
| `https_listener_arn` | string | HTTPS listener ARN |
| `route53_record_name` | string | Route53 record name |
| `target_groups` | map(object) | All target group information |

## Cost Considerations

**Load Balancer Costs:**
- Base: $16.20/month (730 hours)
- LCU (Load Balancer Capacity Units): Variable based on:
  - New connections per second
  - Active connections
  - Processed bytes
  - Rule evaluations

**Typical Costs:**
- Small application: $20-30/month
- Medium application: $30-50/month
- High traffic application: $50-100+/month

**Cost Optimization:**
- Use single ALB with path-based routing instead of multiple ALBs
- Review and remove unused target groups
- Optimize health check intervals (longer intervals = lower cost)
- Use CloudFront in front of ALB for static content

## Common Patterns

### Pattern 1: Simple Web Application

```hcl
module "alb" {
  source = "../../modules/networking/alb"
  
  alb_name           = "webapp"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnets
  security_group_ids = [module.security_groups.web_alb_security_group_id]
}

# Register ECS service with target group
module "ecs" {
  source = "../../modules/containers/ecs-service"
  
  target_group_arn = module.alb.default_target_group_arn
  # ...
}
```

### Pattern 2: Blue/Green Deployments

```hcl
module "alb" {
  source = "../../modules/networking/alb"
  
  additional_target_groups = {
    blue = {
      port = 8080
      # ... config
    }
    green = {
      port = 8080
      # ... config
    }
  }
  
  listener_rules = {
    production = {
      action_type      = "forward"
      target_group_key = "blue"  # Switch to "green" for deployment
      # ...
    }
  }
}
```

### Pattern 3: Multi-Tenant Routing

```hcl
module "alb" {
  source = "../../modules/networking/alb"
  
  listener_rules = {
    tenant_a = {
      host_header      = "tenant-a.example.com"
      target_group_key = "tenant_a"
      # ...
    }
    tenant_b = {
      host_header      = "tenant-b.example.com"
      target_group_key = "tenant_b"
      # ...
    }
  }
}
```

## Troubleshooting

### 503 Service Unavailable

**Problem**: ALB returns 503 errors.

**Causes**:
1. No healthy targets in target group
2. Security group not allowing traffic
3. Health check failing

**Solution**:
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw default_target_group_arn)

# Common issues:
# - Security group blocking ALB → target traffic
# - Health check path returns 404
# - Application not listening on configured port
