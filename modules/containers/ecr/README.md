# ECR (Elastic Container Registry) Module

Creates and manages Amazon ECR repositories for storing Docker container images with automated scanning, lifecycle policies, and replication.

## Features

- **Image Scanning**: Automatic vulnerability scanning on push
- **Lifecycle Policies**: Automatic cleanup of old/untagged images
- **Cross-Account Access**: Share images with other AWS accounts
- **Cross-Region Replication**: Replicate images to multiple regions
- **Encryption**: AES-256 or KMS encryption at rest
- **Immutable Tags**: Prevent tag overwrites for production images
- **CloudWatch Monitoring**: Alerts on vulnerabilities

## Usage

### Basic Example

```hcl
module "ecr" {
  source = "../../modules/containers/ecr"
  
  repository_name = "my-app"
  scan_on_push    = true
}

output "repository_url" {
  value = module.ecr.repository_url
}
```

### Production Example with All Features

```hcl
module "ecr" {
  source = "../../modules/containers/ecr"
  
  repository_name      = "production-api"
  image_tag_mutability = "IMMUTABLE"  # Prevent tag overwrites
  
  # Scanning
  scan_on_push         = true
  enable_scan_logging  = true
  
  # Lifecycle Policy - Keep images clean
  enable_lifecycle_policy         = true
  untagged_image_retention_count  = 3      # Keep 3 untagged images
  tagged_image_retention_count    = 20     # Keep 20 tagged images
  image_retention_days            = 90     # Delete images > 90 days old
  tag_prefix_list                 = ["v", "prod", "release"]
  
  # Encryption
  encryption_type = "KMS"
  kms_key_arn     = aws_kms_key.ecr.arn
  
  # Cross-Account Access
  enable_repository_policy = true
  pull_account_ids         = ["123456789012"]  # Allow prod account to pull
  
  # Monitoring
  create_cloudwatch_alarms = true
  vulnerability_threshold  = 0  # Alert on any critical vulnerabilities
  alarm_actions           = [aws_sns_topic.alerts.arn]
  
  tags = {
    Environment = "production"
    Service     = "api"
  }
}
```

### Cross-Region Replication

```hcl
module "ecr" {
  source = "../../modules/containers/ecr"
  
  repository_name = "global-app"
  
  # Replicate to multiple regions
  enable_replication = true
  replication_destinations = [
    {
      region      = "us-west-2"
      registry_id = data.aws_caller_identity.current.account_id
      repository_filter = null
    },
    {
      region      = "eu-west-1"
      registry_id = data.aws_caller_identity.current.account_id
      repository_filter = null
    }
  ]
}
```

### Shared Repository (Multi-Account)

```hcl
# In management account
module "shared_ecr" {
  source = "../../modules/containers/ecr"
  
  repository_name = "shared-base-images"
  
  enable_repository_policy = true
  
  # Allow multiple accounts to pull
  pull_account_ids = [
    "111111111111",  # Dev account
    "222222222222",  # Staging account
    "333333333333"   # Prod account
  ]
  
  # Only management account can push
  push_account_ids = [
    data.aws_caller_identity.current.account_id
  ]
}
```

## Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `repository_name` | string | Name of the ECR repository |

### Repository Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `image_tag_mutability` | string | "MUTABLE" | MUTABLE or IMMUTABLE |
| `scan_on_push` | bool | true | Scan images on push |
| `encryption_type` | string | "AES256" | AES256 or KMS |
| `kms_key_arn` | string | null | KMS key ARN (if encryption_type=KMS) |

### Lifecycle Policy

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_lifecycle_policy` | bool | true | Enable lifecycle policy |
| `untagged_image_retention_count` | number | 3 | Untagged images to keep |
| `tagged_image_retention_count` | number | 10 | Tagged images to keep |
| `image_retention_days` | number | 0 | Delete images older than N days (0=disabled) |
| `tag_prefix_list` | list(string) | ["v", "prod"] | Tag prefixes for retention policy |

### Repository Policy

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_repository_policy` | bool | false | Enable repository policy |
| `pull_account_ids` | list(string) | [] | Account IDs allowed to pull |
| `push_account_ids` | list(string) | [] | Account IDs allowed to push |
| `custom_policy_statements` | list(any) | [] | Additional policy statements |

### Replication

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_replication` | bool | false | Enable cross-region replication |
| `replication_destinations` | list(object) | [] | Replication configuration |

### Scanning

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_registry_scanning` | bool | false | Enable enhanced scanning |
| `scan_type` | string | "BASIC" | BASIC or ENHANCED |
| `enable_scan_logging` | bool | false | Log scan results to CloudWatch |
| `enable_scan_notifications` | bool | false | Send scan notifications |
| `sns_topic_arn` | string | null | SNS topic for notifications |

### Monitoring

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_cloudwatch_alarms` | bool | false | Create CloudWatch alarms |
| `vulnerability_threshold` | number | 0 | Alert threshold for critical vulns |
| `alarm_actions` | list(string) | [] | SNS topic ARNs for alarms |
| `log_retention_days` | number | 30 | CloudWatch log retention |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `repository_arn` | string | ECR repository ARN |
| `repository_url` | string | Full repository URL for docker push/pull |
| `repository_name` | string | Repository name |
| `registry_id` | string | Registry ID (AWS account ID) |

## Cost Considerations

**ECR Pricing**:
- **Storage**: $0.10/GB/month
- **Data Transfer Out**: 
  - To internet: $0.09/GB
  - To same region: Free
  - Cross-region: $0.02/GB

**Typical Costs**:
```
Small project (5 images, 500 MB each):
- Storage: 2.5 GB × $0.10 = $0.25/month

Medium project (20 images, 1 GB each):
- Storage: 20 GB × $0.10 = $2.00/month

Large project (100 images, 2 GB each):
- Storage: 200 GB × $0.10 = $20.00/month
```

**Cost Optimization**:
1. **Enable lifecycle policies**: Delete old/unused images automatically
2. **Compress images**: Use multi-stage builds, alpine base images
3. **Avoid duplication**: Use image tags efficiently
4. **Regional proximity**: Keep ECR in same region as ECS

## Image Management

### Pushing Images

```bash
# Get ECR repository URL
REPO_URL=$(terraform output -raw repository_url)

# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $REPO_URL

# Build image
docker build -t my-app:latest .

# Tag image
docker tag my-app:latest $REPO_URL:latest
docker tag my-app:latest $REPO_URL:v1.2.3

# Push image
docker push $REPO_URL:latest
docker push $REPO_URL:v1.2.3
```

### Pulling Images

```bash
# From same account
aws ecr get-login-password | docker login --username AWS --password-stdin $REPO_URL
docker pull $REPO_URL:latest

# From different account (requires repository policy)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com
docker pull 123456789012.dkr.ecr.us-east-1.amazonaws.com/shared-app:latest
```

### Image Scanning

```bash
# Manually trigger scan
aws ecr start-image-scan \
  --repository-name my-app \
  --image-id imageTag=latest

# Get scan results
aws ecr describe-image-scan-findings \
  --repository-name my-app \
  --image-id imageTag=latest

# List images by vulnerability count
aws ecr describe-images \
  --repository-name my-app \
  --query 'sort_by(imageDetails, &imageScanFindingsSummary.findingSeverityCounts.CRITICAL)' \
  --output table
```

## Lifecycle Policy Examples

### Example 1: Keep Only Recent Images

```hcl
lifecycle_rules = [{
  id      = "keep-last-10"
  enabled = true
  
  # Keep only the 10 most recent images
  tagged_image_retention_count = 10
  
  # Delete untagged images immediately
  untagged_image_retention_count = 1
}]
```

### Example 2: Production Tag Protection

```hcl
lifecycle_rules = [{
  id      = "protect-production"
  enabled = true
  
  # Keep all production-tagged images
  tag_prefix_list = ["prod", "release"]
  tagged_image_retention_count = 100
  
  # Keep dev/feature images for 30 days
  image_retention_days = 30
}]
```

### Example 3: Aggressive Cleanup

```hcl
lifecycle_rules = [{
  id      = "aggressive-cleanup"
  enabled = true
  
  # Keep only 3 images total
  tagged_image_retention_count   = 3
  untagged_image_retention_count = 0  # Delete untagged immediately
  
  # Delete images older than 14 days
  image_retention_days = 14
}]
```

## Common Patterns

### Pattern 1: Development Workflow

```hcl
module "dev_ecr" {
  source = "../../modules/containers/ecr"
  
  repository_name      = "dev-app"
  image_tag_mutability = "MUTABLE"  # Allow tag overwrites
  
  # Aggressive cleanup for dev
  enable_lifecycle_policy        = true
  untagged_image_retention_count = 1
  tagged_image_retention_count   = 5
  image_retention_days           = 14
  
  scan_on_push = true
}
```

### Pattern 2: Production Workflow

```hcl
module "prod_ecr" {
  source = "../../modules/containers/ecr"
  
  repository_name      = "prod-app"
  image_tag_mutability = "IMMUTABLE"  # Prevent accidents
  
  # Keep more images
  enable_lifecycle_policy      = true
  tagged_image_retention_count = 50
  tag_prefix_list             = ["v", "release"]
  
  # Enhanced security
  scan_on_push            = true
  enable_scan_logging     = true
  enable_scan_notifications = true
  sns_topic_arn          = aws_sns_topic.security_alerts.arn
  
  # Encryption
  encryption_type = "KMS"
  kms_key_arn     = aws_kms_key.ecr.arn
  
  # Monitoring
  create_cloudwatch_alarms = true
  vulnerability_threshold  = 0
  alarm_actions           = [aws_sns_topic.alerts.arn]
}
```

### Pattern 3: Shared Base Images

```hcl
# Central account
module "base_images" {
  source = "../../modules/containers/ecr"
  
  repository_name = "base-images"
  
  # Allow all accounts to pull
  enable_repository_policy = true
  pull_account_ids = [
    "111111111111",  # Dev
    "222222222222",  # Staging
    "333333333333"   # Prod
  ]
  
  # Only central account can push
  # (default - no push_account_ids specified)
  
  # Keep base images long-term
  enable_lifecycle_policy      = true
  tagged_image_retention_count = 100
  image_retention_days         = 365
}
```

### Pattern 4: Multi-Region Deployment

```hcl
module "global_ecr" {
  source = "../../modules/containers/ecr"
  
  repository_name = "global-app"
  
  # Primary in us-east-1
  # Replicate to other regions
  enable_replication = true
  replication_destinations = [
    {
      region                = "us-west-2"
      registry_id           = data.aws_caller_identity.current.account_id
      repository_filter     = null
      enable_replication_time_control = true
      enable_replication_metrics      = true
    },
    {
      region      = "eu-west-1"
      registry_id = data.aws_caller_identity.current.account_id
      repository_filter = null
      enable_replication_time_control = true
      enable_replication_metrics      = true
    }
  ]
}
```

## Troubleshooting

### Issue: Cannot Push to Repository

**Error**: `denied: User: arn:aws:iam::123456789012:user/developer is not authorized to perform: ecr:PutImage`

**Solution**:
```bash
# Check IAM permissions
aws iam get-user-policy --user-name developer --policy-name ecr-access

# Developer needs these permissions:
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ],
    "Resource": "*"
  }]
}
```

### Issue: ECS Can't Pull Image

**Error**: `CannotPullContainerError: API error (500): Get https://123456789012.dkr.ecr.us-east-1.amazonaws.com/v2/: net/http: request canceled`

**Solution**:
```bash
# Check ECS execution role has ECR permissions
# The module automatically creates this, but verify:
aws iam get-role-policy \
  --role-name <service-name>-ecs-execution-role \
  --policy-name ecr-access

# Ensure ECS task is in VPC with NAT Gateway or VPC endpoint
# Private subnet tasks need NAT Gateway to reach ECR

# Or create VPC endpoint for ECR (no NAT cost)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.us-east-1.ecr.api"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.us-east-1.ecr.dkr"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}
```

### Issue: Image Scan Shows Vulnerabilities

**Finding**: Critical vulnerabilities in base image.

**Solution**:
```bash
# View scan details
aws ecr describe-image-scan-findings \
  --repository-name my-app \
  --image-id imageTag=latest \
  --query 'imageScanFindings.findings[?severity==`CRITICAL`]'

# Common fixes:
# 1. Update base image
FROM node:18-alpine  # Use alpine for smaller attack surface

# 2. Update packages
RUN apk update && apk upgrade

# 3. Remove unnecessary packages
RUN apk del <package-name>

# 4. Use distroless images
FROM gcr.io/distroless/nodejs:18

# Rebuild and rescan
docker build -t my-app:latest .
docker push $REPO_URL:latest
aws ecr start-image-scan --repository-name my-app --image-id imageTag=latest
```

### Issue: Repository Policy Not Working

**Problem**: Cross-account pull fails despite policy.

**Solution**:
```bash
# Verify repository policy
aws ecr get-repository-policy --repository-name my-app

# Ensure destination account has permissions
# In destination account IAM:
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ],
    "Resource": "arn:aws:ecr:us-east-1:123456789012:repository/my-app"
  }]
}

# Authenticate in destination account
aws ecr get-login-password \
  --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com

# Test pull
docker pull 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:latest
```

### Issue: High Storage Costs

**Problem**: ECR storage costs are increasing.

**Solution**:
```bash
# Check repository size
aws ecr describe-repositories --repository-names my-app

# List all images with sizes
aws ecr describe-images \
  --repository-name my-app \
  --query 'sort_by(imageDetails, &imagePushedAt)' \
  --output table

# Enable aggressive lifecycle policy
enable_lifecycle_policy        = true
untagged_image_retention_count = 1
tagged_image_retention_count   = 10
image_retention_days           = 30

# Manually delete old images
aws ecr batch-delete-image \
  --repository-name my-app \
  --image-ids imageTag=old-tag-1 imageTag=old-tag-2

# Optimize image size
# Use multi-stage builds
FROM node:18 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:18-alpine
COPY --from=builder /app/node_modules ./node_modules
COPY . .
CMD ["node", "index.js"]
```

## Best Practices

### 1. Image Tagging Strategy

```bash
# Use semantic versioning
docker tag my-app:latest $REPO_URL:v1.2.3
docker tag my-app:latest $REPO_URL:v1.2
docker tag my-app:latest $REPO_URL:v1
docker tag my-app:latest $REPO_URL:latest

# Include git SHA for traceability
GIT_SHA=$(git rev-parse --short HEAD)
docker tag my-app:latest $REPO_URL:$GIT_SHA

# Environment-specific tags
docker tag my-app:latest $REPO_URL:prod-latest
docker tag my-app:latest $REPO_URL:staging-latest
```

### 2. Security Scanning

```hcl
# Always enable scanning
scan_on_push = true

# For production, enable enhanced scanning
enable_registry_scanning = true
scan_type               = "ENHANCED"  # AWS Inspector

# Monitor scan results
enable_scan_notifications = true
sns_topic_arn            = aws_sns_topic.security.arn

# Alert on critical vulnerabilities
create_cloudwatch_alarms = true
vulnerability_threshold  = 0
```

### 3. Image Optimization

```dockerfile
# Use specific versions, not 'latest'
FROM node:18.17.1-alpine3.18 

# Multi-stage builds
FROM node:18 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:18-alpine
COPY --from=builder /app/node_modules ./node_modules
COPY . .

# Non-root user
USER node

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s \
  CMD node healthcheck.js
```

### 4. Lifecycle Management

```hcl
# Development: Aggressive cleanup
enable_lifecycle_policy        = true
untagged_image_retention_count = 1
tagged_image_retention_count   = 5
image_retention_days           = 14

# Production: Keep history
enable_lifecycle_policy        = true
tagged_image_retention_count   = 50
tag_prefix_list               = ["v", "release", "prod"]
# No expiration for production images
```

## Integration Examples

### With ECS

```hcl
module "ecr" {
  source = "../../modules/containers/ecr"
  
  repository_name = "my-app"
}

module "ecs" {
  source = "../../modules/containers/ecs-service"
  
  container_image = "${module.ecr.repository_url}:latest"
  # ...
}
```

### With CI/CD Pipeline

```yaml
# .github/workflows/build-push.yml
name: Build and Push to ECR

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Login to ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1
      
      - name: Build and push
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: my-app
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG $ECR_REGISTRY/$ECR_REPOSITORY:latest
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
```

### With CodeBuild

```hcl
resource "aws_codebuild_project" "build" {
  name = "my-app-build"
  
  artifacts {
    type = "NO_ARTIFACTS"
  }
  
  environment {
    type            = "LINUX_CONTAINER"
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    privileged_mode = true  # Required for Docker
    
    environment_variable {
      name  = "ECR_REPOSITORY_URL"
      value = module.ecr.repository_url
    }
  }
  
  source {
    type      = "GITHUB"
    location  = "https://github.com/myorg/myapp"
    buildspec = "buildspec.yml"
  }
}
```

## Monitoring Dashboard

```hcl
resource "aws_cloudwatch_dashboard" "ecr" {
  dashboard_name = "ECR-${var.repository_name}"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECR", "RepositoryPullCount", { stat = "Sum" }],
            [".", "RepositoryPushCount", { stat = "Sum" }]
          ]
          period = 300
          stat   = "Sum"
          region = "us-east-1"
          title  = "Push/Pull Activity"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECR", "HighSeverityVulnerabilities", { stat = "Maximum" }],
            [".", "CriticalSeverityVulnerabilities", { stat = "Maximum" }]
          ]
          period = 300
          stat   = "Maximum"
          region = "us-east-1"
          title  = "Security Vulnerabilities"
        }
      }
    ]
  })
}
```

## References

- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)
- [ECR Pricing](https://aws.amazon.com/ecr/pricing/)
- [ECR Best Practices](https://docs.aws.amazon.com/AmazonECR/latest/userguide/best-practices.html)
- [Image Scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html)
- [Lifecycle Policies](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html)
