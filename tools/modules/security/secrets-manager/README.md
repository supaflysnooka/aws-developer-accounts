# Secrets Manager Module

Creates and manages AWS Secrets Manager secrets for storing sensitive information like database passwords, API keys, and credentials with automatic rotation support.

## Features

- **Secure Storage**: Encrypted at rest with KMS
- **Automatic Rotation**: Lambda-based password rotation
- **Version Control**: Track all versions of secrets
- **Fine-grained Access**: IAM and resource policies
- **Audit Trail**: CloudWatch Logs integration
- **Recovery**: 7-30 day recovery window
- **Cross-Region Replication**: Disaster recovery support

## Usage

### Basic Example

```hcl
module "db_secret" {
  source = "../../modules/security/secrets-manager"
  
  secret_name            = "prod-database-password"
  generate_secret_string = true
  username               = "admin"
  
  tags = {
    Environment = "production"
    Application = "main-app"
  }
}

output "secret_arn" {
  value     = module.db_secret.secret_arn
  sensitive = true
}
```

### Manual Secret Value

```hcl
module "api_key" {
  source = "../../modules/security/secrets-manager"
  
  secret_name   = "third-party-api-key"
  secret_string = jsonencode({
    api_key    = "sk_live_..."
    api_secret = "secret_..."
  })
  
  description = "Third-party API credentials"
}
```

### Complete Production Example

```hcl
module "production_secret" {
  source = "../../modules/security/secrets-manager"
  
  secret_name = "prod-rds-master-password"
  description = "Production RDS master password"
  
  # Generate secure password
  generate_secret_string    = true
  username                  = "db_admin"
  password_length           = 32
  password_include_special  = true
  
  # Encryption
  kms_key_id = aws_kms_key.secrets.arn
  
  # Recovery
  recovery_window_in_days = 30
  
  # Resource Policy
  resource_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = aws_iam_role.app.arn
      }
      Action   = "secretsmanager:GetSecretValue"
      Resource = "*"
    }]
  })
  
  # Automatic Rotation
  enable_rotation      = true
  rotation_lambda_arn  = aws_lambda_function.rotate_secret.arn
  rotation_days        = 30
  
  # Monitoring
  enable_scan_notifications = true
  create_cloudwatch_alarms = true
  alarm_actions           = [aws_sns_topic.security_alerts.arn]
  
  tags = {
    Environment = "production"
    Compliance  = "required"
    Backup      = "required"
  }
}
```

### RDS Integration

```hcl
# RDS automatically creates secret
module "database" {
  source = "../../modules/databases/rds"
  
  db_name     = "myapp"
  db_username = "admin"
  
  # Let RDS manage the password in Secrets Manager
  manage_master_user_password = true
  
  # ... other config
}

# Access the secret in application
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = module.database.secret_arn
}

locals {
  db_creds = jsondecode(data.aws_secretsmanager_secret_version.db_password.secret_string)
}

# Use in Lambda environment
resource "aws_lambda_function" "app" {
  # ... other config
  
  environment {
    variables = {
      DB_HOST     = local.db_creds.host
      DB_PORT     = local.db_creds.port
      DB_NAME     = local.db_creds.dbname
      DB_USERNAME = local.db_creds.username
      DB_PASSWORD = local.db_creds.password
    }
  }
}
```

### Rotation Lambda Function

```hcl
module "db_secret" {
  source = "../../modules/security/secrets-manager"
  
  secret_name            = "rotating-db-password"
  generate_secret_string = true
  username               = "app_user"
  
  # Enable rotation with custom Lambda
  enable_rotation         = true
  create_rotation_lambda  = true
  rotation_lambda_zip_file = "lambda/rotate_secret.zip"
  rotation_lambda_handler  = "index.handler"
  rotation_lambda_runtime  = "python3.11"
  rotation_days           = 30
  
  # Lambda needs VPC access to reach RDS
  rotation_lambda_subnet_ids         = module.vpc.private_subnets
  rotation_lambda_security_group_ids = [aws_security_group.lambda_rotation.id]
  
  rotation_lambda_environment_variables = {
    DB_ENDPOINT = module.database.db_endpoint
  }
}
```

## Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `secret_name` | string | Name of the secret (must be unique) |

### Secret Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `description` | string | "" | Secret description |
| `kms_key_id` | string | null | KMS key ARN for encryption |
| `recovery_window_in_days` | number | 30 | Recovery window (7-30 days) |

### Secret Value

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `secret_string` | string | null | Secret value (JSON format) |
| `generate_secret_string` | bool | false | Auto-generate password |
| `username` | string | "admin" | Username for generated secret |
| `password_length` | number | 32 | Generated password length |
| `password_include_special` | bool | true | Include special characters |

### Resource Policy

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_policy` | string | null | Resource-based policy JSON |

### Rotation

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_rotation` | bool | false | Enable automatic rotation |
| `rotation_lambda_arn` | string | null | Rotation Lambda ARN |
| `rotation_days` | number | 30 | Days between rotations |
| `create_rotation_lambda` | bool | false | Create rotation Lambda |
| `rotation_lambda_zip_file` | string | null | Lambda zip file path |
| `rotation_lambda_handler` | string | "lambda_function.lambda_handler" | Lambda handler |
| `rotation_lambda_runtime` | string | "python3.11" | Lambda runtime |
| `rotation_lambda_timeout` | number | 30 | Lambda timeout (seconds) |
| `rotation_lambda_environment_variables` | map(string) | {} | Lambda env variables |
| `rotation_lambda_subnet_ids` | list(string) | [] | VPC subnet IDs |
| `rotation_lambda_security_group_ids` | list(string) | [] | Security group IDs |

### Monitoring

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_cloudwatch_alarms` | bool | false | Create CloudWatch alarms |
| `alarm_actions` | list(string) | [] | SNS topic ARNs |
| `log_retention_days` | number | 30 | Log retention days |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `secret_arn` | string | Secret ARN |
| `secret_id` | string | Secret ID |
| `secret_name` | string | Secret name |
| `secret_version_id` | string | Current version ID |
| `rotation_lambda_arn` | string | Rotation Lambda ARN (if created) |
| `rotation_enabled` | bool | Whether rotation is enabled |

## Cost Considerations

**Secrets Manager Pricing**:
- **Secret storage**: $0.40 per secret per month
- **API calls**: $0.05 per 10,000 calls
- **Rotation**: Lambda costs (typically < $0.01/rotation)

**Monthly Cost Examples**:
```
5 secrets, 100K API calls:
- Secrets: 5 × $0.40 = $2.00
- API calls: 10 × $0.05 = $0.50
Total: $2.50/month

20 secrets, 1M API calls:
- Secrets: 20 × $0.40 = $8.00
- API calls: 100 × $0.05 = $5.00
Total: $13/month

100 secrets, 10M API calls:
- Secrets: 100 × $0.40 = $40
- API calls: 1,000 × $0.05 = $50
Total: $90/month
```

**Cost Optimization**:
1. Cache secrets in application (reduce API calls)
2. Delete unused secrets
3. Use parameter store for non-sensitive config ($0 for standard parameters)
4. Batch secret retrievals when possible

## Accessing Secrets

### From Lambda (Python)

```python
import json
import boto3
from botocore.exceptions import ClientError

def get_secret(secret_name):
    """Retrieve secret from Secrets Manager"""
    client = boto3.client('secretsmanager')
    
    try:
        response = client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])
        return secret
    except ClientError as e:
        print(f"Error retrieving secret: {e}")
        raise

def lambda_handler(event, context):
    # Get database credentials
    db_secret = get_secret('prod-database-password')
    
    # Use credentials
    username = db_secret['username']
    password = db_secret['password']
    
    # Connect to database
    # ...
```

### From Lambda (Node.js)

```javascript
const AWS = require('aws-sdk');
const secretsManager = new AWS.SecretsManager();

async function getSecret(secretName) {
  try {
    const data = await secretsManager.getSecretValue({
      SecretId: secretName
    }).promise();
    
    return JSON.parse(data.SecretString);
  } catch (error) {
    console.error('Error retrieving secret:', error);
    throw error;
  }
}

exports.handler = async (event) => {
  const dbCreds = await getSecret('prod-database-password');
  
  // Use credentials
  const { username, password, host, port } = dbCreds;
  
  // Connect to database
  // ...
};
```

### From ECS Task

```hcl
module "ecs_service" {
  source = "../../modules/containers/ecs-service"
  
  # ... other config
  
  # Reference secrets in task definition
  secrets = {
    DB_PASSWORD = module.db_secret.secret_arn
    API_KEY     = module.api_secret.secret_arn
  }
}
```

### From Command Line

```bash
# Get secret value
aws secretsmanager get-secret-value \
  --secret-id prod-database-password \
  --query SecretString --output text

# Parse JSON secret
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id prod-database-password \
  --query SecretString --output text)

USERNAME=$(echo $SECRET | jq -r '.username')
PASSWORD=$(echo $SECRET | jq -r '.password')

# Use in script
psql -h $DB_HOST -U $USERNAME -d myapp
```

## Rotation Lambda Example

### Python Rotation Lambda

```python
import json
import boto3
import pymysql
import os

def lambda_handler(event, context):
    """
    Rotate database password
    """
    service_client = boto3.client('secretsmanager')
    
    # Get the secret ARN and token from the event
    arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']
    
    # Get the secret metadata
    metadata = service_client.describe_secret(SecretId=arn)
    
    if step == "createSecret":
        create_secret(service_client, arn, token)
    elif step == "setSecret":
        set_secret(service_client, arn, token)
    elif step == "testSecret":
        test_secret(service_client, arn, token)
    elif step == "finishSecret":
        finish_secret(service_client, arn, token)
    else:
        raise ValueError("Invalid step parameter")

def create_secret(service_client, arn, token):
    """Generate new password"""
    # Get current secret
    current_secret = service_client.get_secret_value(
        SecretId=arn,
        VersionStage="AWSCURRENT"
    )
    current_dict = json.loads(current_secret['SecretString'])
    
    # Generate new password
    new_password = service_client.get_random_password(
        PasswordLength=32,
        ExcludeCharacters='/@"\'\\'
    )
    
    # Create new secret version
    current_dict['password'] = new_password['RandomPassword']
    
    service_client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(current_dict),
        VersionStages=['AWSPENDING']
    )

def set_secret(service_client, arn, token):
    """Update password in database"""
    # Get pending secret
    pending_secret = service_client.get_secret_value(
        SecretId=arn,
        VersionId=token,
        VersionStage="AWSPENDING"
    )
    pending_dict = json.loads(pending_secret['SecretString'])
    
    # Connect to database with current credentials
    current_secret = service_client.get_secret_value(
        SecretId=arn,
        VersionStage="AWSCURRENT"
    )
    current_dict = json.loads(current_secret['SecretString'])
    
    # Update password in database
    conn = pymysql.connect(
        host=os.environ['DB_ENDPOINT'].split(':')[0],
        user=current_dict['username'],
        password=current_dict['password'],
        database=current_dict['dbname']
    )
    
    with conn.cursor() as cursor:
        cursor.execute(
            f"ALTER USER '{pending_dict['username']}' IDENTIFIED BY '{pending_dict['password']}'"
        )
    conn.commit()
    conn.close()

def test_secret(service_client, arn, token):
    """Test new password works"""
    # Get pending secret
    pending_secret = service_client.get_secret_value(
        SecretId=arn,
        VersionId=token,
        VersionStage="AWSPENDING"
    )
    pending_dict = json.loads(pending_secret['SecretString'])
    
    # Try to connect with new credentials
    conn = pymysql.connect(
        host=os.environ['DB_ENDPOINT'].split(':')[0],
        user=pending_dict['username'],
        password=pending_dict['password'],
        database=pending_dict['dbname']
    )
    conn.close()

def finish_secret(service_client, arn, token):
    """Finalize rotation"""
    # Move AWSCURRENT to old version
    metadata = service_client.describe_secret(SecretId=arn)
    current_version = None
    for version in metadata["VersionIdsToStages"]:
        if "AWSCURRENT" in metadata["VersionIdsToStages"][version]:
            current_version = version
            break
    
    # Update version stages
    service_client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version
    )
```

## Common Patterns

### Pattern 1: Database Credentials

```hcl
module "db_credentials" {
  source = "../../modules/security/secrets-manager"
  
  secret_name            = "${var.app_name}-db-credentials"
  generate_secret_string = true
  username               = "app_user"
  password_length        = 32
  
  # Rotate every 30 days
  enable_rotation     = true
  rotation_lambda_arn = aws_lambda_function.rotate_db_password.arn
  rotation_days       = 30
  
  tags = {
    Application = var.app_name
    Purpose     = "database-credentials"
  }
}

# Use in RDS
resource "aws_db_instance" "main" {
  # ... other config
  
  username = jsondecode(data.aws_secretsmanager_secret_version.db_creds.secret_string)["username"]
  password = jsondecode(data.aws_secretsmanager_secret_version.db_creds.secret_string)["password"]
}

data "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = module.db_credentials.secret_id
}
```

### Pattern 2: API Keys

```hcl
module "api_keys" {
  source = "../../modules/security/secrets-manager"
  
  secret_name = "third-party-api-keys"
  secret_string = jsonencode({
    stripe_key    = "sk_live_..."
    sendgrid_key  = "SG...."
    twilio_sid    = "AC..."
    twilio_token  = "..."
  })
  
  # Allow specific roles to access
  resource_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = [
          aws_iam_role.app.arn,
          aws_iam_role.worker.arn
        ]
      }
      Action   = "secretsmanager:GetSecretValue"
      Resource = "*"
    }]
  })
}
```

### Pattern 3: OAuth Credentials

```hcl
module "oauth_secret" {
  source = "../../modules/security/secrets-manager"
  
  secret_name = "oauth-client-credentials"
  secret_string = jsonencode({
    client_id     = "..."
    client_secret = "..."
    redirect_uri  = "https://app.example.com/callback"
  })
  
  kms_key_id = aws_kms_key.oauth.arn
  
  tags = {
    Compliance = "required"
  }
}
```

### Pattern 4: SSH Keys

```hcl
module "ssh_key" {
  source = "../../modules/security/secrets-manager"
  
  secret_name = "deployment-ssh-key"
  secret_string = jsonencode({
    private_key = file("~/.ssh/deploy_rsa")
    public_key  = file("~/.ssh/deploy_rsa.pub")
  })
  
  # No rotation for SSH keys
  enable_rotation = false
}
```

## Security Best Practices

### 1. Use Resource Policies

```hcl
resource_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect = "Allow"
    Principal = {
      AWS = aws_iam_role.app.arn
    }
    Action = "secretsmanager:GetSecretValue"
    Resource = "*"
    Condition = {
      StringEquals = {
        "secretsmanager:VersionStage" = "AWSCURRENT"
      }
    }
  }]
})
```

### 2. Enable Rotation

```hcl
# Always enable rotation for database passwords
enable_rotation     = true
rotation_lambda_arn = aws_lambda_function.rotate.arn
rotation_days       = 30  # Monthly rotation
```

### 3. Use KMS Encryption

```hcl
# Custom KMS key for sensitive secrets
resource "aws_kms_key" "secrets" {
  description             = "Secrets Manager encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

module "secret" {
  source = "../../modules/security/secrets-manager"
  
  secret_name = "sensitive-data"
  kms_key_id  = aws_kms_key.secrets.arn
  # ...
}
```

### 4. Least Privilege IAM

```hcl
# Grant minimal permissions
resource "aws_iam_policy" "secret_access" {
  name = "secret-read-only"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = module.db_secret.secret_arn
      Condition = {
        StringEquals = {
          "secretsmanager:VersionStage" = "AWSCURRENT"
        }
      }
    }]
  })
}
```

### 5. Enable Logging

```hcl
# CloudTrail for API calls
resource "aws_cloudtrail" "secrets" {
  name                          = "secrets-trail"
  s3_bucket_name               = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    
    data_resource {
      type = "AWS::SecretsManager::Secret"
      values = ["arn:aws:secretsmanager:*:*:secret:*"]
    }
  }
}
```

## Troubleshooting

### Issue: ResourceNotFoundException

**Problem**: Secret not found.

**Solutions**:
```bash
# 1. Check secret exists
aws secretsmanager list-secrets \
  --query 'SecretList[?Name==`my-secret`]'

# 2. Check secret ARN is correct
terraform output secret_arn

# 3. Check IAM permissions
aws secretsmanager get-secret-value \
  --secret-id my-secret

# 4. Check if secret was deleted
aws secretsmanager list-secrets \
  --include-planned-deletion
```

### Issue: AccessDeniedException

**Problem**: Permission denied accessing secret.

**Solutions**:
```bash
# 1. Check IAM policy
aws iam get-role-policy \
  --role-name my-app-role \
  --policy-name secret-access

# Policy should include:
{
  "Effect": "Allow",
  "Action": "secretsmanager:GetSecretValue",
  "Resource": "arn:aws:secretsmanager:*:*:secret:my-secret-*"
}

# 2. Check resource policy
aws secretsmanager get-resource-policy \
  --secret-id my-secret

# 3. Check KMS key permissions
aws kms describe-key --key-id <key-id>
```

### Issue: Rotation Failing

**Problem**: Secret rotation fails.

**Solutions**:
```bash
# 1. Check Lambda logs
aws logs tail /aws/lambda/rotate-secret --follow

# 2. Common issues:
# - Lambda can't reach database (VPC/security groups)
# - Lambda timeout too short
# - Database user doesn't exist
# - Insufficient database permissions

# 3. Test rotation manually
aws secretsmanager rotate-secret \
  --secret-id my-secret \
  --rotation-lambda-arn <lambda-arn>

# 4. Check Lambda has permissions
aws lambda get-policy --function-name rotate-secret

# Should allow Secrets Manager to invoke
```

### Issue: DecryptionFailureException

**Problem**: Cannot decrypt secret.

**Solutions**:
```bash
# 1. Check KMS key policy
aws kms get-key-policy \
  --key-id <key-id> \
  --policy-name default

# 2. Grant decrypt permission to role
{
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::123456789012:role/app-role"
  },
  "Action": [
    "kms:Decrypt",
    "kms:DescribeKey"
  ],
  "Resource": "*"
}

# 3. Verify key is enabled
aws kms describe-key --key-id <key-id> \
  --query 'KeyMetadata.KeyState'
```

### Issue: High Costs

**Problem**: Secrets Manager costs are high.

**Solutions**:
```bash
# 1. Check number of secrets
aws secretsmanager list-secrets --query 'length(SecretList)'

# 2. Delete unused secrets
aws secretsmanager delete-secret \
  --secret-id unused-secret \
  --force-delete-without-recovery

# 3. Check API call volume
# Enable CloudTrail and analyze secretsmanager:GetSecretValue calls

# 4. Implement caching
# Cache secrets in application for 1 hour
# Reduce API calls by 99%

# Python example:
import time

class SecretCache:
    def __init__(self, ttl=3600):
        self.cache = {}
        self.ttl = ttl
    
    def get(self, secret_name):
        if secret_name in self.cache:
            secret, timestamp = self.cache[secret_name]
            if time.time() - timestamp < self.ttl:
                return secret
        
        # Fetch from Secrets Manager
        secret = fetch_secret(secret_name)
        self.cache[secret_name] = (secret, time.time())
        return secret

cache = SecretCache()
secret = cache.get('my-secret')
```

## Monitoring

### CloudWatch Metrics

```hcl
# Monitor rotation failures
resource "aws_cloudwatch_metric_alarm" "rotation_failed" {
  alarm_name          = "secret-rotation-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RotationFailed"
  namespace           = "AWS/SecretsManager"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Secret rotation failed"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    SecretId = module.db_secret.secret_id
  }
}
```

### Audit Access

```sql
-- Query CloudTrail for secret access
SELECT
  eventTime,
  userIdentity.principalId,
  requestParameters.secretId,
  sourceIPAddress
FROM cloudtrail_logs
WHERE eventName = 'GetSecretValue'
  AND requestParameters.secretId LIKE '%prod%'
ORDER BY eventTime DESC
LIMIT 100;
```

## Best Practices

1. **Use Secrets Manager for sensitive data** (passwords, API keys, tokens)
2. **Enable automatic rotation** for database passwords
3. **Use KMS encryption** for highly sensitive secrets
4. **Implement caching** to reduce API calls and costs
5. **Use resource policies** for fine-grained access control
6. **Enable CloudTrail** for audit logging
7. **Never hardcode secrets** in code or environment variables
8. **Set appropriate recovery window** (30 days for production)
9. **Tag secrets** for organization and cost allocation
10. **Regular cleanup** of unused secrets

## References

- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [Secrets Manager Pricing](https://aws.amazon.com/secrets-manager/pricing/)
- [Rotation Lambda Examples](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html)
- [Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [IAM Policies](https://docs.aws.amazon.com/secretsmanager/latest/userguide/auth-and-access.html)
