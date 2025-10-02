# API Gateway Module

Creates and manages Amazon API Gateway for building REST and HTTP APIs with Lambda integration, authorization, throttling, and custom domains.

## Features

- **HTTP APIs**: Modern, low-latency APIs (recommended)
- **REST APIs**: Full-featured APIs with more customization
- **Lambda Integration**: Direct Lambda function invocation
- **CORS**: Cross-origin resource sharing configuration
- **Custom Domains**: Use your own domain names
- **Throttling**: Rate limiting and burst control
- **Authorization**: JWT, IAM, Lambda authorizers
- **CloudWatch**: Access logs and metrics
- **VPC Links**: Connect to private resources

## Usage

### Basic HTTP API

```hcl
module "api" {
  source = "../../modules/api/api-gateway"
  
  api_name = "my-api"
  api_type = "http"  # Modern, lower cost
  
  enable_cors        = true
  cors_allow_origins = ["https://app.example.com"]
}

output "api_endpoint" {
  value = module.api.api_endpoint
}
```

### Complete HTTP API with Lambda

```hcl
module "api" {
  source = "../../modules/api/api-gateway"
  
  api_name        = "user-api"
  api_type        = "http"
  api_description = "User management API"
  
  # CORS Configuration
  enable_cors             = true
  cors_allow_origins      = ["https://app.example.com", "http://localhost:3000"]
  cors_allow_methods      = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
  cors_allow_headers      = ["Content-Type", "Authorization", "X-Api-Key"]
  cors_allow_credentials  = true
  cors_max_age           = 300
  
  # Lambda Integrations
  lambda_integrations = {
    get_users = {
      lambda_arn           = aws_lambda_function.get_users.arn
      lambda_name          = aws_lambda_function.get_users.function_name
      route_key            = "GET /users"
      timeout_milliseconds = 30000
      authorization_type   = "JWT"
      authorizer_id        = aws_apigatewayv2_authorizer.jwt.id
    }
    create_user = {
      lambda_arn           = aws_lambda_function.create_user.arn
      lambda_name          = aws_lambda_function.create_user.function_name
      route_key            = "POST /users"
      timeout_milliseconds = 30000
      authorization_type   = "JWT"
      authorizer_id        = aws_apigatewayv2_authorizer.jwt.id
    }
    get_user = {
      lambda_arn           = aws_lambda_function.get_user.arn
      lambda_name          = aws_lambda_function.get_user.function_name
      route_key            = "GET /users/{id}"
      timeout_milliseconds = 30000
      authorization_type   = "JWT"
      authorizer_id        = aws_apigatewayv2_authorizer.jwt.id
    }
  }
  
  # Stage Configuration
  stage_name  = "prod"
  auto_deploy = true
  
  # Throttling
  enable_throttling      = true
  throttling_burst_limit = 5000
  throttling_rate_limit  = 10000
  
  # Logging
  enable_access_logs   = true
  log_retention_days   = 30
  
  # Monitoring
  create_cloudwatch_alarms = true
  error_4xx_threshold      = 100
  error_5xx_threshold      = 50
  latency_threshold        = 1000
  alarm_actions           = [aws_sns_topic.alerts.arn]
  
  tags = {
    Environment = "production"
    API         = "user-service"
  }
}
```

### REST API

```hcl
module "rest_api" {
  source = "../../modules/api/api-gateway"
  
  api_name = "legacy-api"
  api_type = "rest"
  
  endpoint_type = "REGIONAL"
  
  # REST API has more features but higher cost
  # Use for: API keys, usage plans, request validation
  
  stage_name = "v1"
  
  enable_access_logs = true
}
```

### API with Custom Domain

```hcl
module "api" {
  source = "../../modules/api/api-gateway"
  
  api_name = "production-api"
  api_type = "http"
  
  # Lambda integrations...
  lambda_integrations = {
    # ... routes
  }
  
  # Custom Domain
  create_custom_domain = true
  domain_name         = "api.example.com"
  certificate_arn     = aws_acm_certificate.api.arn
  
  # Route53 Integration
  create_route53_record = true
  route53_zone_id      = data.aws_route53_zone.main.zone_id
  
  api_mapping_key = null  # Mount at root path
}

# Clients call: https://api.example.com/users
```

### WebSocket API

```hcl
# WebSocket APIs require custom configuration
resource "aws_apigatewayv2_api" "websocket" {
  name                       = "chat-websocket"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

resource "aws_apigatewayv2_integration" "connect" {
  api_id           = aws_apigatewayv2_api.websocket.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.connect.invoke_arn
}

resource "aws_apigatewayv2_route" "connect" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connect.id}"
}
```

### Private API (VPC Link)

```hcl
module "private_api" {
  source = "../../modules/api/api-gateway"
  
  api_name = "internal-api"
  api_type = "http"
  
  # Create VPC Link
  create_vpc_link              = true
  vpc_link_subnet_ids          = module.vpc.private_subnets
  vpc_link_security_group_ids  = [aws_security_group.api_vpc_link.id]
  
  # Connect to private ALB
  # Requires custom integration configuration
}
```

## Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `api_name` | string | Name of the API |

### API Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `api_type` | string | "http" | http or rest |
| `api_description` | string | "" | API description |
| `endpoint_type` | string | "REGIONAL" | REST API: REGIONAL, EDGE, PRIVATE |

### CORS Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_cors` | bool | false | Enable CORS |
| `cors_allow_origins` | list(string) | ["*"] | Allowed origins |
| `cors_allow_methods` | list(string) | ["*"] | Allowed methods |
| `cors_allow_headers` | list(string) | [] | Allowed headers |
| `cors_expose_headers` | list(string) | [] | Exposed headers |
| `cors_allow_credentials` | bool | false | Allow credentials |
| `cors_max_age` | number | 0 | Max age in seconds |

### Stage Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `stage_name` | string | "$default" | Stage name |
| `auto_deploy` | bool | true | Auto-deploy changes |

### Lambda Integrations

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `lambda_integrations` | map(object) | {} | Lambda integration configurations |

**Lambda Integration Object**:
```hcl
{
  lambda_arn           = string
  lambda_name          = string
  route_key            = string  # e.g., "GET /users"
  timeout_milliseconds = optional(number, 30000)
  authorization_type   = optional(string, "NONE")
  authorizer_id        = optional(string)
}
```

### Throttling

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_throttling` | bool | false | Enable throttling |
| `throttling_burst_limit` | number | 5000 | Burst limit |
| `throttling_rate_limit` | number | 10000 | Steady-state rate limit |

### Logging

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_access_logs` | bool | false | Enable access logs |
| `log_retention_days` | number | 30 | Log retention in days |

### Custom Domain

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_custom_domain` | bool | false | Create custom domain |
| `domain_name` | string | "" | Custom domain name |
| `certificate_arn` | string | "" | ACM certificate ARN |
| `create_route53_record` | bool | false | Create Route53 A record |
| `route53_zone_id` | string | "" | Route53 hosted zone ID |
| `api_mapping_key` | string | null | API mapping path |

### VPC Link

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_vpc_link` | bool | false | Create VPC link |
| `vpc_link_subnet_ids` | list(string) | [] | VPC link subnet IDs |
| `vpc_link_security_group_ids` | list(string) | [] | VPC link security group IDs |

### WAF

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `web_acl_arn` | string | null | WAF WebACL ARN (REST only) |

### Monitoring

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_cloudwatch_alarms` | bool | false | Create CloudWatch alarms |
| `error_4xx_threshold` | number | 100 | 4XX error threshold |
| `error_5xx_threshold` | number | 50 | 5XX error threshold |
| `latency_threshold` | number | 1000 | Latency threshold (ms) |
| `alarm_actions` | list(string) | [] | SNS topic ARNs |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `api_id` | string | API Gateway ID |
| `api_arn` | string | API Gateway ARN |
| `api_endpoint` | string | API endpoint URL |
| `api_execution_arn` | string | Execution ARN for permissions |
| `stage_id` | string | Stage ID |
| `stage_arn` | string | Stage ARN |
| `custom_domain_name` | string | Custom domain name (if created) |
| `route53_record_name` | string | Route53 record name (if created) |

## Cost Considerations

**API Gateway Pricing**:

**HTTP APIs** (recommended):
- $1.00 per million requests
- First 300 million requests/month: $1.00/million
- Next 700 million: $0.90/million
- Over 1 billion: $0.80/million

**REST APIs**:
- $3.50 per million requests
- First 333 million requests/month
- Caching: $0.020/hour per GB

**Data Transfer**:
- First 10 TB: $0.09/GB out to internet
- Regional data transfer: $0.01/GB

**Monthly Cost Examples**:
```
Small API (1M requests/month):
- HTTP API: $1.00
- REST API: $3.50

Medium API (100M requests/month):
- HTTP API: $100
- REST API: $350

Large API (1B requests/month):
- HTTP API: ~$920
- REST API: $3,500
```

**Cost Optimization**:
1. Use HTTP APIs instead of REST APIs (70% savings)
2. Enable caching to reduce backend calls
3. Implement throttling to prevent abuse
4. Use regional endpoints (avoid CloudFront)
5. Batch requests where possible

## Common Patterns

### Pattern 1: CRUD API

```hcl
module "api" {
  source = "../../modules/api/api-gateway"
  
  api_name = "items-api"
  api_type = "http"
  
  lambda_integrations = {
    list_items = {
      lambda_arn  = aws_lambda_function.list_items.arn
      lambda_name = aws_lambda_function.list_items.function_name
      route_key   = "GET /items"
    }
    get_item = {
      lambda_arn  = aws_lambda_function.get_item.arn
      lambda_name = aws_lambda_function.get_item.function_name
      route_key   = "GET /items/{id}"
    }
    create_item = {
      lambda_arn  = aws_lambda_function.create_item.arn
      lambda_name = aws_lambda_function.create_item.function_name
      route_key   = "POST /items"
    }
    update_item = {
      lambda_arn  = aws_lambda_function.update_item.arn
      lambda_name = aws_lambda_function.update_item.function_name
      route_key   = "PUT /items/{id}"
    }
    delete_item = {
      lambda_arn  = aws_lambda_function.delete_item.arn
      lambda_name = aws_lambda_function.delete_item.function_name
      route_key   = "DELETE /items/{id}"
    }
  }
  
  enable_cors        = true
  cors_allow_origins = ["https://app.example.com"]
  cors_allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}
```

### Pattern 2: Microservices Gateway

```hcl
module "api_gateway" {
  source = "../../modules/api/api-gateway"
  
  api_name = "microservices-gateway"
  api_type = "http"
  
  # Route to different services
  lambda_integrations = {
    # User service
    users = {
      lambda_arn  = aws_lambda_function.user_service.arn
      lambda_name = aws_lambda_function.user_service.function_name
      route_key   = "ANY /users/{proxy+}"
    }
    # Order service
    orders = {
      lambda_arn  = aws_lambda_function.order_service.arn
      lambda_name = aws_lambda_function.order_service.function_name
      route_key   = "ANY /orders/{proxy+}"
    }
    # Product service
    products = {
      lambda_arn  = aws_lambda_function.product_service.arn
      lambda_name = aws_lambda_function.product_service.function_name
      route_key   = "ANY /products/{proxy+}"
    }
  }
  
  enable_cors = true
}
```

### Pattern 3: API with JWT Authorization

```hcl
# JWT Authorizer
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = module.api.api_id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "jwt-authorizer"
  
  jwt_configuration {
    audience = ["https://api.example.com"]
    issuer   = "https://cognito-idp.us-east-1.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}

module "api" {
  source = "../../modules/api/api-gateway"
  
  api_name = "secure-api"
  api_type = "http"
  
  lambda_integrations = {
    protected_route = {
      lambda_arn         = aws_lambda_function.protected.arn
      lambda_name        = aws_lambda_function.protected.function_name
      route_key          = "GET /protected"
      authorization_type = "JWT"
      authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
    }
  }
}
```

### Pattern 4: Public + Private Routes

```hcl
module "api" {
  source = "../../modules/api/api-gateway"
  
  api_name = "mixed-api"
  api_type = "http"
  
  lambda_integrations = {
    # Public route (no auth)
    health = {
      lambda_arn         = aws_lambda_function.health.arn
      lambda_name        = aws_lambda_function.health.function_name
      route_key          = "GET /health"
      authorization_type = "NONE"
    }
    public_info = {
      lambda_arn         = aws_lambda_function.info.arn
      lambda_name        = aws_lambda_function.info.function_name
      route_key          = "GET /info"
      authorization_type = "NONE"
    }
    # Protected routes (JWT auth)
    user_profile = {
      lambda_arn         = aws_lambda_function.profile.arn
      lambda_name        = aws_lambda_function.profile.function_name
      route_key          = "GET /profile"
      authorization_type = "JWT"
      authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
    }
  }
}
```

## Lambda Function Example

```python
# Lambda function for API Gateway
import json

def lambda_handler(event, context):
    # HTTP API format
    print(f"Event: {json.dumps(event)}")
    
    # Parse request
    http_method = event['requestContext']['http']['method']
    path = event['requestContext']['http']['path']
    
    # Get path parameters
    path_params = event.get('pathParameters', {})
    
    # Get query parameters
    query_params = event.get('queryStringParameters', {})
    
    # Get body
    body = json.loads(event.get('body', '{}'))
    
    # Get headers
    headers = event.get('headers', {})
    
    # Business logic
    if http_method == 'GET' and '/users' in path:
        response_body = {'users': [{'id': 1, 'name': 'John'}]}
    else:
        response_body = {'message': 'Not found'}
    
    # Return response
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(response_body)
    }
```

## Troubleshooting

### Issue: CORS Errors

**Problem**: Browser shows "CORS policy" error.

**Solutions**:
```hcl
# 1. Enable CORS in module
enable_cors        = true
cors_allow_origins = ["https://app.example.com", "http://localhost:3000"]
cors_allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
cors_allow_headers = ["Content-Type", "Authorization"]

# 2. Ensure Lambda returns CORS headers
return {
    'statusCode': 200,
    'headers': {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization'
    },
    'body': json.dumps(response)
}

# 3. Check preflight OPTIONS requests
# API Gateway handles OPTIONS automatically with CORS enabled
```

### Issue: 403 Forbidden

**Problem**: API returns 403 Forbidden.

**Solutions**:
```bash
# 1. Check authorizer configuration
aws apigatewayv2 get-authorizers --api-id <api-id>

# 2. Verify JWT token
# Decode token at jwt.io and check:
# - Issuer matches authorizer issuer
# - Audience matches authorizer audience
# - Token not expired

# 3. Check Lambda permissions
aws lambda get-policy --function-name my-function

# Should have policy allowing API Gateway to invoke
```

### Issue: 502 Bad Gateway

**Problem**: API returns 502 error.

**Solutions**:
```bash
# 1. Check Lambda logs
aws logs tail /aws/lambda/my-function --follow

# Common causes:
# - Lambda timeout (increase timeout_milliseconds)
# - Lambda error (check CloudWatch logs)
# - Invalid response format

# 2. Verify Lambda response format
# HTTP API requires:
{
    "statusCode": 200,
    "headers": {"Content-Type": "application/json"},
    "body": "{\"message\":\"success\"}"
}

# 3. Check Lambda execution role
# Ensure it has permissions for any AWS services it calls
```

### Issue: High Latency

**Problem**: API responses are slow.

**Solutions**:
```bash
# 1. Check Lambda cold starts
# - Use Provisioned Concurrency for critical functions
# - Optimize Lambda package size
# - Use Lambda SnapStart (Java)

# 2. Enable X-Ray tracing
resource "aws_apigatewayv2_stage" "main" {
  # ... other config
  
  default_route_settings {
    detailed_metrics_enabled = true
  }
}

# 3. Check Lambda timeout
timeout_milliseconds = 30000  # 30 seconds

# 4. Monitor metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name IntegrationLatency \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 300 \
  --statistics Average
```

### Issue: Throttling Errors

**Problem**: Getting 429 Too Many Requests.

**Solutions**:
```hcl
# Increase throttle limits
enable_throttling      = true
throttling_burst_limit = 10000  # Was 5000
throttling_rate_limit  = 20000  # Was 10000

# Or implement retry logic in client
import time
import requests

def call_api_with_retry(url, max_retries=3):
    for i in range(max_retries):
        response = requests.get(url)
        if response.status_code != 429:
            return response
        time.sleep(2 ** i)  # Exponential backoff
    return None
```

## Best Practices

1. **Use HTTP APIs** for new projects (lower cost, better performance)
2. **Enable CORS** properly to avoid browser issues
3. **Implement throttling** to prevent abuse
4. **Use custom domains** for production
5. **Enable access logs** for debugging
6. **Use JWT authorizers** for authentication
7. **Version your APIs** (/v1, /v2)
8. **Monitor latency and errors** with CloudWatch
9. **Implement retry logic** in clients
10. **Use X-Ray** for distributed tracing

## Integration Examples

### With Lambda

Already shown in usage examples above.

### With Cognito (User Pools)

```hcl
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = module.api.api_id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-authorizer"
  
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.client.id]
    issuer   = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.pool.id}"
  }
}
```

### With WAF (REST API only)

```hcl
module "rest_api" {
  source = "../../modules/api/api-gateway"
  
  api_name = "protected-api"
  api_type = "rest"
  
  web_acl_arn = aws_wafv2_web_acl.api.arn
}

resource "aws_wafv2_web_acl" "api" {
  name  = "api-protection"
  scope = "REGIONAL"
  
  default_action {
    allow {}
  }
  
  rule {
    name     = "RateLimitRule"
    priority = 1
    
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    
    action {
      block {}
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "RateLimitRule"
      sampled_requests_enabled  = true
    }
  }
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name               = "APIWebACL"
    sampled_requests_enabled  = true
  }
}
```

## References

- [API Gateway Documentation](https://docs.aws.amazon.com/apigateway/)
- [HTTP APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html)
- [REST APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-rest-api.html)
- [API Gateway Pricing](https://aws.amazon.com/api-gateway/pricing/)
- [Best Practices](https://docs.aws.amazon.com/apigateway/latest/developerguide/best-practices.html)
