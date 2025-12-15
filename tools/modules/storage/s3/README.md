# S3 (Simple Storage Service) Module

Creates and manages Amazon S3 buckets with versioning, lifecycle policies, encryption, replication, and event notifications for object storage.

## Features

- **Versioning**: Track all versions of objects
- **Encryption**: Server-side encryption (AES-256 or KMS)
- **Lifecycle Policies**: Automatic transitions and expiration
- **CORS**: Cross-origin resource sharing configuration
- **Replication**: Cross-region and same-region replication
- **Event Notifications**: Trigger Lambda, SQS, or SNS on object changes
- **Public Access Block**: Prevent accidental public exposure
- **Object Lock**: WORM (write-once-read-many) compliance

## Usage

### Basic Example

```hcl
module "s3_bucket" {
  source = "../../modules/storage/s3"
  
  bucket_name       = "my-app-data-${random_id.suffix.hex}"
  enable_versioning = true
}

output "bucket_name" {
  value = module.s3_bucket.bucket_name
}
```

### Complete Production Example

```hcl
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

module "production_bucket" {
  source = "../../modules/storage/s3"
  
  bucket_name       = "prod-app-data-${random_id.bucket_suffix.hex}"
  force_destroy     = false  # Prevent accidental deletion
  
  # Versioning
  enable_versioning = true
  enable_mfa_delete = false  # Requires root account
  
  # Encryption
  sse_algorithm     = "aws:kms"
  kms_master_key_id = aws_kms_key.s3.arn
  bucket_key_enabled = true  # Reduce KMS costs
  
  # Public Access Block
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  
  # Lifecycle Rules
  lifecycle_rules = [
    {
      id      = "transition-to-ia"
      enabled = true
      filter  = { prefix = "logs/" }
      
      transition_to_ia_days          = 30
      transition_to_glacier_days     = 90
      transition_to_deep_archive_days = 180
      expiration_days                = 365
      
      noncurrent_version_transition_to_ia_days = 30
      noncurrent_version_expiration_days       = 90
      
      abort_incomplete_multipart_upload_days = 7
    },
    {
      id      = "delete-temp-files"
      enabled = true
      filter  = { prefix = "tmp/" }
      
      expiration_days = 7
    }
  ]
  
  # CORS
  cors_rules = [{
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["https://example.com"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }]
  
  # Logging
  enable_logging       = true
  logging_target_bucket = module.log_bucket.bucket_name
  logging_target_prefix = "s3-access-logs/"
  
  # Replication
  enable_replication = true
  replication_rules = [{
    id                      = "replicate-all"
    priority                = 1
    enabled                 = true
    prefix                  = ""
    destination_bucket_arn  = "arn:aws:s3:::prod-app-data-backup"
    storage_class          = "STANDARD_IA"
    enable_replication_time_control = true
    enable_replication_metrics      = true
    replicate_delete_markers        = true
  }]
  
  # Event Notifications
  enable_notifications = true
  lambda_notifications = [{
    lambda_arn    = aws_lambda_function.process_upload.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
    filter_suffix = ".jpg"
  }]
  
  tags = {
    Environment = "production"
    Backup      = "required"
  }
}
```

### Static Website Hosting

```hcl
module "website_bucket" {
  source = "../../modules/storage/s3"
  
  bucket_name = "my-website-${random_id.suffix.hex}"
  
  # Allow public read for website
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
  
  # Website configuration (requires custom resource)
  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::my-website-${random_id.suffix.hex}/*"
    }]
  })
  
  # CORS for API calls
  cors_rules = [{
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }]
}

# Upload website files
resource "aws_s3_object" "index" {
  bucket       = module.website_bucket.bucket_name
  key          = "index.html"
  source       = "website/index.html"
  content_type = "text/html"
  etag         = filemd5("website/index.html")
}
```

### Data Lake with Intelligent Tiering

```hcl
module "data_lake" {
  source = "../../modules/storage/s3"
  
  bucket_name = "analytics-data-lake-${random_id.suffix.hex}"
  
  enable_versioning = true
  storage_encrypted = true
  
  # Intelligent Tiering for cost optimization
  enable_intelligent_tiering          = true
  intelligent_tiering_archive_days    = 90
  intelligent_tiering_deep_archive_days = 180
  
  # Inventory for large datasets
  enable_inventory               = true
  inventory_destination_bucket_arn = module.inventory_bucket.bucket_arn
  inventory_destination_prefix     = "inventory/"
  inventory_frequency             = "Daily"
  
  lifecycle_rules = [{
    id      = "archive-old-data"
    enabled = true
    filter  = null
    
    transition_to_glacier_days = 365
    noncurrent_version_expiration_days = 30
  }]
}
```

### Application File Storage

```hcl
module "app_storage" {
  source = "../../modules/storage/s3"
  
  bucket_name = "app-uploads-${random_id.suffix.hex}"
  
  enable_versioning = false  # Don't need versions for uploads
  storage_encrypted = true
  
  # Auto-delete old uploads
  lifecycle_rules = [{
    id      = "cleanup-uploads"
    enabled = true
    filter  = { prefix = "temp/" }
    expiration_days = 1
  }]
  
  # CORS for file uploads from browser
  cors_rules = [{
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT"]
    allowed_origins = ["https://app.example.com"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }]
  
  # Notify Lambda on upload
  enable_notifications = true
  lambda_notifications = [{
    lambda_arn    = aws_lambda_function.process_image.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
  }]
}
```

## Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `bucket_name` | string | Globally unique bucket name |

### Bucket Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `force_destroy` | bool | false | Allow deletion with objects inside |

### Versioning

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_versioning` | bool | false | Enable object versioning |
| `enable_mfa_delete` | bool | false | Require MFA for deletion |

### Encryption

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `sse_algorithm` | string | "AES256" | AES256 or aws:kms |
| `kms_master_key_id` | string | null | KMS key ARN (if using KMS) |
| `bucket_key_enabled` | bool | false | Use S3 Bucket Keys (reduce KMS costs) |

### Public Access Block

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `block_public_acls` | bool | true | Block public ACLs |
| `block_public_policy` | bool | true | Block public bucket policies |
| `ignore_public_acls` | bool | true | Ignore public ACLs |
| `restrict_public_buckets` | bool | true | Restrict public bucket policies |

### Lifecycle Rules

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `lifecycle_rules` | list(object) | [] | Lifecycle rule configurations |

**Lifecycle Rule Object**:
```hcl
{
  id                                        = string
  enabled                                   = bool
  filter                                    = optional(object)
  transition_to_ia_days                    = optional(number)
  transition_to_glacier_days               = optional(number)
  transition_to_deep_archive_days          = optional(number)
  expiration_days                          = optional(number)
  noncurrent_version_transition_to_ia_days = optional(number)
  noncurrent_version_expiration_days       = optional(number)
  abort_incomplete_multipart_upload_days   = optional(number)
}
```

### CORS

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cors_rules` | list(object) | [] | CORS rule configurations |

### Logging

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_logging` | bool | false | Enable S3 access logging |
| `logging_target_bucket` | string | null | Bucket to store logs |
| `logging_target_prefix` | string | null | Log prefix |

### Replication

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_replication` | bool | false | Enable cross-region replication |
| `replication_rules` | list(object) | [] | Replication rule configurations |

### Event Notifications

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_notifications` | bool | false | Enable event notifications |
| `lambda_notifications` | list(object) | [] | Lambda function notifications |
| `sns_notifications` | list(object) | [] | SNS topic notifications |
| `sqs_notifications` | list(object) | [] | SQS queue notifications |

### Intelligent Tiering

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_intelligent_tiering` | bool | false | Enable intelligent tiering |
| `intelligent_tiering_archive_days` | number | 90 | Days to archive tier |
| `intelligent_tiering_deep_archive_days` | number | 180 | Days to deep archive |

### Inventory

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_inventory` | bool | false | Enable S3 inventory |
| `inventory_destination_bucket_arn` | string | null | Destination bucket ARN |
| `inventory_destination_prefix` | string | null | Destination prefix |
| `inventory_frequency` | string | "Daily" | Daily or Weekly |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `bucket_id` | string | Bucket name |
| `bucket_arn` | string | Bucket ARN |
| `bucket_domain_name` | string | Bucket domain name |
| `bucket_regional_domain_name` | string | Regional domain name |

## Cost Considerations

**S3 Pricing** (us-east-1):

**Storage Classes**:
| Class | $/GB/month | Use Case |
|-------|------------|----------|
| Standard | $0.023 | Frequently accessed |
| Standard-IA | $0.0125 | Infrequent access |
| One Zone-IA | $0.01 | Infrequent, non-critical |
| Glacier Instant | $0.004 | Archive with instant retrieval |
| Glacier Flexible | $0.0036 | Archive, 1-5 min retrieval |
| Glacier Deep Archive | $0.00099 | Long-term archive, 12 hrs |
| Intelligent-Tiering | $0.023 + $0.0025/1000 objects | Automatic optimization |

**Additional Costs**:
- **Requests**: $0.0004 per 1,000 PUT/POST, $0.0004 per 10,000 GET
- **Data Transfer Out**: $0.09/GB to internet (first 10 TB)
- **Lifecycle Transitions**: $0.01 per 1,000 requests
- **Replication**: Standard rates + transfer costs

**Monthly Cost Examples**:
```
Small app (10 GB, 100K requests):
- Storage: 10 × $0.023 = $0.23
- Requests: negligible
Total: ~$0.25/month

Medium app (1 TB, 1M requests):
- Storage: 1,000 × $0.023 = $23
- Requests: ~$0.10
Total: ~$23/month

Large app (10 TB with lifecycle):
- Hot data (1 TB): $23
- Warm data (3 TB IA): 3,000 × $0.0125 = $37.50
- Cold data (6 TB Glacier): 6,000 × $0.004 = $24
Total: ~$85/month
```

**Cost Optimization**:
1. Use lifecycle policies to transition old data
2. Enable Intelligent-Tiering for unpredictable access
3. Use S3 Select/Glacier Select to query data in place
4. Delete incomplete multipart uploads
5. Use requester pays for public datasets
6. Compress objects before upload

## Common Patterns

### Pattern 1: Application File Storage

```hcl
module "uploads" {
  source = "../../modules/storage/s3"
  
  bucket_name = "app-uploads-${random_id.suffix.hex}"
  
  # Lifecycle
  lifecycle_rules = [{
    id      = "delete-old-uploads"
    enabled = true
    filter  = { prefix = "temp/" }
    expiration_days = 7
  }]
  
  # CORS for browser uploads
  cors_rules = [{
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["https://app.example.com"]
    allowed_headers = ["*"]
  }]
  
  # Trigger processing
  enable_notifications = true
  lambda_notifications = [{
    lambda_arn = aws_lambda_function.resize_image.arn
    events     = ["s3:ObjectCreated:*"]
  }]
}
```

### Pattern 2: Backup Storage

```hcl
module "backups" {
  source = "../../modules/storage/s3"
  
  bucket_name = "database-backups-${random_id.suffix.hex}"
  
  enable_versioning = true
  storage_encrypted = true
  kms_master_key_id = aws_kms_key.backups.arn
  
  # Lifecycle for cost optimization
  lifecycle_rules = [{
    id      = "archive-old-backups"
    enabled = true
    filter  = null
    
    transition_to_ia_days          = 30
    transition_to_glacier_days     = 90
    transition_to_deep_archive_days = 365
    expiration_days                = 2555  # 7 years
  }]
  
  # Lock backups (compliance)
  enable_object_lock = true
  object_lock_mode   = "GOVERNANCE"
  object_lock_days   = 30
}
```

### Pattern 3: Static Website

```hcl
module "website" {
  source = "../../modules/storage/s3"
  
  bucket_name = "my-website-${random_id.suffix.hex}"
  
  # Allow public read
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
  
  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicRead"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::my-website-${random_id.suffix.hex}/*"
    }]
  })
  
  cors_rules = [{
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
  }]
}

# Use with CloudFront
resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name = module.website.bucket_regional_domain_name
    origin_id   = "S3-Website"
  }
  # ... CloudFront config
}
```

### Pattern 4: Log Aggregation

```hcl
module "logs" {
  source = "../../modules/storage/s3"
  
  bucket_name = "application-logs-${random_id.suffix.hex}"
  
  # Lifecycle for log retention
  lifecycle_rules = [{
    id      = "expire-old-logs"
    enabled = true
    filter  = null
    
    transition_to_ia_days      = 90
    transition_to_glacier_days = 180
    expiration_days            = 365
    
    abort_incomplete_multipart_upload_days = 1
  }]
  
  # Enable inventory for analysis
  enable_inventory               = true
  inventory_destination_bucket_arn = module.inventory_bucket.bucket_arn
  inventory_frequency             = "Daily"
}
```

## Lifecycle Policy Examples

### Example 1: Standard Web Application

```hcl
lifecycle_rules = [
  {
    id      = "optimize-storage"
    enabled = true
    filter  = null  # Apply to all objects
    
    # Move to IA after 30 days
    transition_to_ia_days = 30
    
    # Move to Glacier after 90 days
    transition_to_glacier_days = 90
    
    # Delete after 1 year
    expiration_days = 365
    
    # Clean up old versions
    noncurrent_version_transition_to_ia_days = 30
    noncurrent_version_expiration_days       = 90
    
    # Clean up failed uploads
    abort_incomplete_multipart_upload_days = 7
  }
]
```

### Example 2: Compliance (7-year retention)

```hcl
lifecycle_rules = [
  {
    id      = "compliance-archive"
    enabled = true
    filter  = { prefix = "compliance/" }
    
    # Move to Glacier immediately
    transition_to_glacier_days = 1
    
    # Move to Deep Archive after 1 year
    transition_to_deep_archive_days = 365
    
    # Keep for 7 years
    expiration_days = 2555
  }
]
```

### Example 3: Temporary Files

```hcl
lifecycle_rules = [
  {
    id      = "delete-temp"
    enabled = true
    filter  = { prefix = "temp/" }
    
    # Delete after 1 day
    expiration_days = 1
  },
  {
    id      = "delete-uploads"
    enabled = true
    filter  = { prefix = "uploads/" }
    
    # Delete after 7 days
    expiration_days = 7
  }
]
```

## Access Patterns

### Presigned URLs

```python
# Python - Generate presigned URL for upload
import boto3

s3_client = boto3.client('s3')
presigned_url = s3_client.generate_presigned_url(
    'put_object',
    Params={
        'Bucket': 'my-bucket',
        'Key': 'uploads/file.jpg',
        'ContentType': 'image/jpeg'
    },
    ExpiresIn=3600  # 1 hour
)

# Frontend can now upload directly to S3
# POST to presigned_url with file
```

```javascript
// JavaScript - Upload with presigned URL
const uploadFile = async (file, presignedUrl) => {
  const response = await fetch(presignedUrl, {
    method: 'PUT',
    body: file,
    headers: {
      'Content-Type': file.type
    }
  });
  
  return response.ok;
};
```

### IAM Policy for Application

```hcl
resource "aws_iam_policy" "app_s3_access" {
  name = "app-s3-access"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${module.app_storage.bucket_arn}/uploads/*"
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = module.app_storage.bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["uploads/*"]
          }
        }
      }
    ]
  })
}
```

## Troubleshooting

### Issue: Access Denied

**Problem**: Cannot access objects in bucket.

**Solutions**:
```bash
# 1. Check bucket policy
aws s3api get-bucket-policy --bucket my-bucket

# 2. Check public access block
aws s3api get-public-access-block --bucket my-bucket

# 3. Check IAM permissions
aws iam simulate-principal-policy \
  --policy-source-arn <user-arn> \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::my-bucket/*

# 4. Check object ACL
aws s3api get-object-acl --bucket my-bucket --key file.txt

# 5. For public access, ensure:
block_public_acls       = false
block_public_policy     = false
ignore_public_acls      = false
restrict_public_buckets = false
```

### Issue: CORS Errors

**Problem**: Browser shows CORS error when uploading.

**Solutions**:
```hcl
# Configure CORS properly
cors_rules = [{
  allowed_headers = ["*"]  # Or specific headers
  allowed_methods = ["GET", "PUT", "POST", "DELETE"]
  allowed_origins = [
    "https://app.example.com",
    "http://localhost:3000"  # For development
  ]
  expose_headers  = ["ETag", "x-amz-request-id"]
  max_age_seconds = 3000
}]

# Verify CORS config
aws s3api get-bucket-cors --bucket my-bucket
```

### Issue: High Costs

**Problem**: S3 costs are unexpectedly high.

**Solutions**:
```bash
# 1. Check storage usage
aws s3 ls s3://my-bucket --recursive --summarize

# 2. Check storage class distribution
aws s3api list-objects-v2 \
  --bucket my-bucket \
  --query 'Contents[].{Key:Key,Size:Size,StorageClass:StorageClass}'

# 3. Find large objects
aws s3 ls s3://my-bucket --recursive --human-readable \
  | sort -k3 -h -r | head -20

# 4. Check incomplete multipart uploads
aws s3api list-multipart-uploads --bucket my-bucket

# 5. Clean up incomplete uploads
aws s3api abort-multipart-upload \
  --bucket my-bucket \
  --key <key> \
  --upload-id <upload-id>

# 6. Enable lifecycle policy
lifecycle_rules = [{
  id      = "cleanup"
  enabled = true
  abort_incomplete_multipart_upload_days = 7
  transition_to_ia_days = 30
  expiration_days = 365
}]
```

### Issue: Slow Upload/Download

**Problem**: Transfers are slow.

**Solutions**:
```bash
# 1. Use AWS CLI with multipart
aws s3 cp large-file.zip s3://my-bucket/ \
  --storage-class STANDARD_IA

# 2. Use AWS SDK with transfer acceleration
s3_client = boto3.client('s3', config=Config(
    s3={'use_accelerate_endpoint': True}
))

# 3. Enable transfer acceleration
resource "aws_s3_bucket_accelerate_configuration" "main" {
  bucket = module.s3_bucket.bucket_name
  status = "Enabled"
}

# 4. Use CloudFront for downloads
```

## Monitoring

### CloudWatch Metrics

```hcl
# Alarm on high request errors
resource "aws_cloudwatch_metric_alarm" "s3_errors" {
  alarm_name          = "${var.bucket_name}-high-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xxErrors"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "High error rate in S3 bucket"
  
  dimensions = {
    BucketName = module.s3_bucket.bucket_name
  }
}
```

### S3 Inventory

```hcl
# Enable daily inventory
enable_inventory               = true
inventory_destination_bucket_arn = aws_s3_bucket.inventory.arn
inventory_frequency             = "Daily"

# Query inventory with Athena
resource "aws_athena_database" "s3_inventory" {
  name   = "s3_inventory"
  bucket = aws_s3_bucket.query_results.bucket
}

# Run queries
# SELECT * FROM s3_inventory WHERE storage_class = 'GLACIER'
```

## Best Practices

1. **Always block public access** unless explicitly needed
2. **Enable versioning** for important data
3. **Use lifecycle policies** to optimize costs
4. **Enable encryption** at rest (KMS for sensitive data)
5. **Use IAM roles** for access, not IAM users
6. **Implement bucket policies** for fine-grained control
7. **Enable logging** for security auditing
8. **Use CloudFront** for content delivery
9. **Tag buckets** for cost allocation
10. **Regular cleanup** of old versions and incomplete uploads

## References

- [AWS S3 Documentation](https://docs.aws.amazon.com/s3/)
- [S3 Pricing](https://aws.amazon.com/s3/pricing/)
- [S3 Storage Classes](https://aws.amazon.com/s3/storage-classes/)
- [S3 Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/best-practices.html)
- [S3 Security](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
