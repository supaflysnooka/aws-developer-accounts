# modules/api/api-gateway/main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "api/api-gateway"
  })
}

# API Gateway (HTTP API or REST API)
resource "aws_apigatewayv2_api" "main" {
  count = var.api_type == "http" ? 1 : 0
  
  name          = var.api_name
  protocol_type = "HTTP"
  description   = var.api_description
  
  # CORS Configuration
  dynamic "cors_configuration" {
    for_each = var.enable_cors ? [1] : []
    content {
      allow_credentials = var.cors_allow_credentials
      allow_headers     = var.cors_allow_headers
      allow_methods     = var.cors_allow_methods
      allow_origins     = var.cors_allow_origins
      expose_headers    = var.cors_expose_headers
      max_age          = var.cors_max_age
    }
  }
  
  tags = merge(local.common_tags, {
    Name = var.api_name
    Type = "http-api"
  })
}

# REST API Gateway
resource "aws_api_gateway_rest_api" "main" {
  count = var.api_type == "rest" ? 1 : 0
  
  name        = var.api_name
  description = var.api_description
  
  endpoint_configuration {
    types = [var.endpoint_type]
  }
  
  tags = merge(local.common_tags, {
    Name = var.api_name
    Type = "rest-api"
  })
}

# API Gateway Stage (HTTP API)
resource "aws_apigatewayv2_stage" "main" {
  count = var.api_type == "http" ? 1 : 0
  
  api_id      = aws_apigatewayv2_api.main[0].id
  name        = var.stage_name
  auto_deploy = var.auto_deploy
  
  # Access Logs
  dynamic "access_log_settings" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn
      format = jsonencode({
        requestId      = "$context.requestId"
        ip             = "$context.identity.sourceIp"
        requestTime    = "$context.requestTime"
        httpMethod     = "$context.httpMethod"
        routeKey       = "$context.routeKey"
        status         = "$context.status"
        protocol       = "$context.protocol"
        responseLength = "$context.responseLength"
        integrationError = "$context.integrationErrorMessage"
      })
    }
  }
  
  # Throttling
  dynamic "default_route_settings" {
    for_each = var.enable_throttling ? [1] : []
    content {
      throttling_burst_limit = var.throttling_burst_limit
      throttling_rate_limit  = var.throttling_rate_limit
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.api_name}-${var.stage_name}"
    Type = "api-stage"
  })
}

# REST API Deployment
resource "aws_api_gateway_deployment" "main" {
  count = var.api_type == "rest" ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.main[0].id
  
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.main[0].body))
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# REST API Stage
resource "aws_api_gateway_stage" "main" {
  count = var.api_type == "rest" ? 1 : 0
  
  deployment_id = aws_api_gateway_deployment.main[0].id
  rest_api_id   = aws_api_gateway_rest_api.main[0].id
  stage_name    = var.stage_name
  
  # Access Logs
  dynamic "access_log_settings" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn
      format = jsonencode({
        requestId      = "$context.requestId"
        ip             = "$context.identity.sourceIp"
        requestTime    = "$context.requestTime"
        httpMethod     = "$context.httpMethod"
        resourcePath   = "$context.resourcePath"
        status         = "$context.status"
        protocol       = "$context.protocol"
        responseLength = "$context.responseLength"
      })
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.api_name}-${var.stage_name}"
    Type = "api-stage"
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "api_gateway" {
  count = var.enable_access_logs ? 1 : 0
  
  name              = "/aws/apigateway/${var.api_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${var.api_name}-logs"
    Type = "log-group"
  })
}

# Lambda Integration (HTTP API)
resource "aws_apigatewayv2_integration" "lambda" {
  for_each = var.api_type == "http" ? var.lambda_integrations : {}
  
  api_id           = aws_apigatewayv2_api.main[0].id
  integration_type = "AWS_PROXY"
  
  integration_uri    = each.value.lambda_arn
  integration_method = "POST"
  payload_format_version = "2.0"
  
  timeout_milliseconds = each.value.timeout_milliseconds
}

# Routes (HTTP API)
resource "aws_apigatewayv2_route" "lambda" {
  for_each = var.api_type == "http" ? var.lambda_integrations : {}
  
  api_id    = aws_apigatewayv2_api.main[0].id
  route_key = each.value.route_key
  target    = "integrations/${aws_apigatewayv2_integration.lambda[each.key].id}"
  
  # Authorization
  authorization_type = each.value.authorization_type
  authorizer_id      = each.value.authorizer_id
}

# Lambda Permission (HTTP API)
resource "aws_lambda_permission" "api_gateway" {
  for_each = var.api_type == "http" ? var.lambda_integrations : {}
  
  statement_id  = "AllowExecutionFromAPIGateway-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.lambda_name
  principal     = "apigateway.amazonaws.com"
  
  source_arn = "${aws_apigatewayv2_api.main[0].execution_arn}/*/*"
}

# VPC Link (for private integrations)
resource "aws_apigatewayv2_vpc_link" "main" {
  count = var.create_vpc_link ? 1 : 0
  
  name               = "${var.api_name}-vpc-link"
  security_group_ids = var.vpc_link_security_group_ids
  subnet_ids         = var.vpc_link_subnet_ids
  
  tags = merge(local.common_tags, {
    Name = "${var.api_name}-vpc-link"
    Type = "vpc-link"
  })
}

# Custom Domain
resource "aws_apigatewayv2_domain_name" "main" {
  count = var.create_custom_domain ? 1 : 0
  
  domain_name = var.domain_name
  
  domain_name_configuration {
    certificate_arn = var.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
  
  tags = merge(local.common_tags, {
    Name = var.domain_name
    Type = "custom-domain"
  })
}

# API Mapping
resource "aws_apigatewayv2_api_mapping" "main" {
  count = var.create_custom_domain && var.api_type == "http" ? 1 : 0
  
  api_id      = aws_apigatewayv2_api.main[0].id
  domain_name = aws_apigatewayv2_domain_name.main[0].id
  stage       = aws_apigatewayv2_stage.main[0].id
  
  api_mapping_key = var.api_mapping_key
}

# Route 53 Record
resource "aws_route53_record" "api" {
  count = var.create_custom_domain && var.create_route53_record ? 1 : 0
  
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  
  alias {
    name                   = aws_apigatewayv2_domain_name.main[0].domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.main[0].domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# WAF Association (REST API only)
resource "aws_wafv2_web_acl_association" "main" {
  count = var.api_type == "rest" && var.web_acl_arn != null ? 1 : 0
  
  resource_arn = aws_api_gateway_stage.main[0].arn
  web_acl_arn  = var.web_acl_arn
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "api_4xx_errors" {
  count = var.create_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.api_name}-high-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = var.api_type == "http" ? "AWS/ApiGateway" : "AWS/ApiGateway"
  period              = "120"
  statistic           = "Sum"
  threshold           = var.error_4xx_threshold
  alarm_description   = "This metric monitors API Gateway 4XX errors"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    ApiName = var.api_name
  }
  
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "api_5xx_errors" {
  count = var.create_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.api_name}-high-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = var.api_type == "http" ? "AWS/ApiGateway" : "AWS/ApiGateway"
  period              = "120"
  statistic           = "Sum"
  threshold           = var.error_5xx_threshold
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    ApiName = var.api_name
  }
  
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  count = var.create_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.api_name}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "IntegrationLatency"
  namespace           = var.api_type == "http" ? "AWS/ApiGateway" : "AWS/ApiGateway"
  period              = "120"
  statistic           = "Average"
  threshold           = var.latency_threshold
  alarm_description   = "This metric monitors API Gateway latency"
  alarm_actions       = var.alarm_actions
  
  dimensions = {
    ApiName = var.api_name
  }
  
  tags = local.common_tags
}

# Data source
data "aws_region" "current" {}
