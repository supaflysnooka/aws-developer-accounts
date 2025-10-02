# RDS (Relational Database Service) Module

Creates and manages Amazon RDS databases with automated backups, encryption, monitoring, and high availability options. Supports PostgreSQL and MySQL engines.

## Features

- **Managed Databases**: PostgreSQL and MySQL support
- **Automatic Backups**: Daily backups with point-in-time recovery
- **Encryption**: At-rest and in-transit encryption
- **Secrets Management**: Passwords stored in AWS Secrets Manager
- **Multi-AZ**: High availability with automatic failover
- **Read Replicas**: Scale read workloads
- **Monitoring**: CloudWatch metrics and Performance Insights
- **Automatic Updates**: Minor version upgrades during maintenance window

## Usage

### Basic Example

```hcl
module "database" {
  source = "../../modules/databases/rds"
  
  db_name     = "myapp"
  db_username = "admin"
  
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.micro"
  
  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.security_groups.database_security_group_id]
  
  manage_master_user_password = true  # Stores in Secrets Manager
}

output "database_endpoint" {
  value = module.database.db_endpoint
}

output "database_secret_arn" {
  value = module.database.secret_arn
}
```

### Production Example

```hcl
module "production_database" {
  source = "../../modules/databases/rds"
  
  # Database Configuration
  db_name     = "production"
  db_username = "app_admin"
  
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.small"
  
  allocated_storage     = 100  # GB
  max_allocated_storage = 500  # Enable storage autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id           = aws_kms_key.rds.arn
  
  # High Availability
  multi_az               = true
  availability_zone      = null  # Auto-select in Multi-AZ
  
  # Networking
  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.security_groups.database_security_group_id]
  publicly_accessible    = false
  
  # Backups
  backup_retention_period      = 30  # 30 days
  backup_window               = "03:00-04:00"  # UTC
  maintenance_window          = "sun:04:00-sun:05:00"
  delete_automated_backups    = false
  copy_tags_to_snapshot       = true
  
  # Updates
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  apply_immediately          = false
  
  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql"]
  performance_insights_enabled    = true
  performance_insights_retention_period = 7
  monitoring_interval           = 60
  
  # Deletion Protection
  deletion_protection      = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "production-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  # Secrets
  manage_master_user_password = true
  
  # Parameters
  parameter_group_family = "postgres15"
  db_parameters = {
    max_connections        = "200"
    shared_buffers        = "256MB"
    effective_cache_size  = "1GB"
    work_mem              = "4MB"
    maintenance_work_mem  = "64MB"
  }
  
  tags = {
    Environment = "production"
    Application = "main-app"
    Backup      = "required"
  }
}
```

### Read Replica

```hcl
# Primary database
module "primary_db" {
  source = "../../modules/databases/rds"
  
  db_name        = "myapp"
  db_username    = "admin"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.small"
  
  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.security_groups.database_security_group_id]
  
  backup_retention_period = 7  # Required for read replicas
  
  manage_master_user_password = true
}

# Read replica
resource "aws_db_instance" "read_replica" {
  identifier             = "myapp-read-replica"
  replicate_source_db    = module.primary_db.db_instance_id
  instance_class         = "db.t3.small"
  
  # Replica can be in different AZ/region
  availability_zone = "us-east-1b"
  
  # Replica-specific settings
  publicly_accessible = false
  skip_final_snapshot = true
  
  tags = {
    Role = "read-replica"
  }
}
```

### MySQL Example

```hcl
module "mysql_database" {
  source = "../../modules/databases/rds"
  
  db_name     = "wordpress"
  db_username = "wp_admin"
  
  engine         = "mysql"
  engine_version = "8.0.35"
  instance_class = "db.t3.micro"
  
  allocated_storage = 20
  storage_type      = "gp3"
  
  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.security_groups.database_security_group_id]
  
  # MySQL-specific parameters
  parameter_group_family = "mysql8.0"
  db_parameters = {
    max_connections        = "150"
    innodb_buffer_pool_size = "256M"
  }
  
  # Enable MySQL logs
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  
  manage_master_user_password = true
}
```

## Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `db_name` | string | Database name |
| `db_username` | string | Master username |
| `engine` | string | Database engine (postgres, mysql) |
| `engine_version` | string | Engine version |
| `instance_class` | string | Instance type |
| `subnet_ids` | list(string) | Database subnet IDs |
| `vpc_security_group_ids` | list(string) | Security group IDs |

### Engine Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `engine` | string | "postgres" | postgres or mysql |
| `engine_version` | string | - | Major.minor version |
| `instance_class` | string | "db.t3.micro" | Instance type |

**Recommended Instance Classes**:
| Class | vCPU | Memory | Use Case | Monthly Cost* |
|-------|------|--------|----------|---------------|
| db.t3.micro | 2 | 1 GB | Dev/test | ~$15 |
| db.t3.small | 2 | 2 GB | Small apps | ~$30 |
| db.t3.medium | 2 | 4 GB | Medium apps | ~$60 |
| db.t4g.micro | 2 | 1 GB | Dev/test (ARM) | ~$12 |
| db.t4g.small | 2 | 2 GB | Small apps (ARM) | ~$24 |

*us-east-1, single-AZ

### Storage

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `allocated_storage` | number | 20 | Initial storage in GB (20-65536) |
| `max_allocated_storage` | number | 0 | Max storage for autoscaling (0=disabled) |
| `storage_type` | string | "gp3" | gp3, gp2, io1, io2 |
| `iops` | number | null | IOPS (for io1/io2) |
| `storage_throughput` | number | null | Throughput MB/s (gp3 only) |
| `storage_encrypted` | bool | true | Enable encryption |
| `kms_key_id` | string | null | KMS key ARN |

### High Availability

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `multi_az` | bool | false | Enable Multi-AZ deployment |
| `availability_zone` | string | null | Specific AZ (single-AZ only) |

### Backups

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `backup_retention_period` | number | 7 | Days to retain backups (0-35) |
| `backup_window` | string | "03:00-04:00" | Daily backup window (UTC) |
| `maintenance_window` | string | "sun:04:00-sun:05:00" | Maintenance window |
| `delete_automated_backups` | bool | true | Delete backups on instance delete |
| `copy_tags_to_snapshot` | bool | true | Copy tags to snapshots |
| `skip_final_snapshot` | bool | false | Skip final snapshot on delete |
| `final_snapshot_identifier` | string | null | Final snapshot name |

### Networking

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `publicly_accessible` | bool | false | Allow public access |
| `port` | number | null | Database port (auto: 5432/3306) |
| `ca_cert_identifier` | string | "rds-ca-rsa2048-g1" | CA certificate |

### Security

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `manage_master_user_password` | bool | false | Use Secrets Manager for password |
| `master_password` | string | null | Master password (if not managed) |
| `iam_database_authentication_enabled` | bool | false | Enable IAM auth |
| `deletion_protection` | bool | false | Prevent accidental deletion |

### Updates

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `auto_minor_version_upgrade` | bool | true | Auto-upgrade minor versions |
| `allow_major_version_upgrade` | bool | false | Allow major version upgrades |
| `apply_immediately` | bool | false | Apply changes immediately |

### Monitoring

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enabled_cloudwatch_logs_exports` | list(string) | [] | Log types to export |
| `performance_insights_enabled` | bool | false | Enable Performance Insights |
| `performance_insights_retention_period` | number | 7 | PI retention days (7-731) |
| `monitoring_interval` | number | 0 | Enhanced monitoring interval (0,1,5,10,15,30,60) |
| `monitoring_role_arn` | string | null | Enhanced monitoring role ARN |

### Parameters

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `parameter_group_family` | string | null | Parameter group family |
| `db_parameters` | map(string) | {} | Database parameters |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `db_instance_id` | string | Database instance identifier |
| `db_instance_arn` | string | Database instance ARN |
| `db_endpoint` | string | Connection endpoint (host:port) |
| `db_address` | string | Hostname only |
| `db_port` | number | Port number |
| `db_name` | string | Database name |
| `db_username` | string | Master username |
| `secret_arn` | string | Secrets Manager secret ARN (if managed) |
| `db_subnet_group_name` | string | DB subnet group name |
| `parameter_group_name` | string | Parameter group name |

## Cost Considerations

**RDS Pricing Components**:
1. **Instance Hours**: Based on instance class
2. **Storage**: $0.115/GB/month (gp3), $0.10/GB/month (gp2)
3. **Backup Storage**: First backup = free, additional = $0.095/GB/month
4. **Data Transfer**: $0.09/GB outbound to internet
5. **Multi-AZ**: 2x instance cost

**Monthly Cost Examples**:
```
Single-AZ PostgreSQL:
- db.t3.micro (2 vCPU, 1 GB): ~$15
- 20 GB storage: ~$2.30
- 7 days backups: ~$1.90 (20 GB × $0.095)
Total: ~$19/month

Multi-AZ PostgreSQL:
- db.t3.small (2 vCPU, 2 GB): ~$60 (×2 = $120)
- 100 GB storage: ~$11.50
- 30 days backups: ~$28.50 (300 GB × $0.095)
Total: ~$160/month

Production PostgreSQL:
- db.t3.medium (2 vCPU, 4 GB) Multi-AZ: ~$240
- 200 GB storage: ~$23
- Backups: ~$57
- Performance Insights: $0.10/vCPU/hour = ~$14
Total: ~$334/month
```

**Cost Optimization**:
1. Use t4g (ARM) instances for 10% savings
2. Use gp3 instead of gp2 storage
3. Single-AZ for dev/test (50% savings)
4. Right-size instances based on metrics
5. Delete old manual snapshots
6. Use Reserved Instances for production (up to 69% discount)

## Connection Examples

### From Application

```python
# Python with psycopg2
import boto3
import psycopg2
import json

# Get credentials from Secrets Manager
client = boto3.client('secretsmanager')
response = client.get_secret_value(SecretId='arn:aws:secretsmanager:...')
secret = json.loads(response['SecretString'])

# Connect to database
conn = psycopg2.connect(
    host=secret['host'],
    port=secret['port'],
    database=secret['dbname'],
    user=secret['username'],
    password=secret['password']
)
```

```javascript
// Node.js with pg
const AWS = require('aws-sdk');
const { Client } = require('pg');

const secretsManager = new AWS.SecretsManager();

async function getDatabaseConnection() {
  const data = await secretsManager.getSecretValue({
    SecretId: 'arn:aws:secretsmanager:...'
  }).promise();
  
  const secret = JSON.parse(data.SecretString);
  
  const client = new Client({
    host: secret.host,
    port: secret.port,
    database: secret.dbname,
    user: secret.username,
    password: secret.password,
    ssl: { rejectUnauthorized: false }
  });
  
  await client.connect();
  return client;
}
```

### From Command Line

```bash
# Get connection info from Terraform
DB_ENDPOINT=$(terraform output -raw db_endpoint)
DB_SECRET=$(terraform output -raw secret_arn)

# Get password from Secrets Manager
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id $DB_SECRET \
  --query SecretString --output text | jq -r '.password')

# Connect to PostgreSQL
psql -h ${DB_ENDPOINT%:*} -U admin -d myapp

# Or MySQL
mysql -h ${DB_ENDPOINT%:*} -u admin -p myapp
```

## Common Patterns

### Pattern 1: Development Database

```hcl
module "dev_database" {
  source = "../../modules/databases/rds"
  
  db_name     = "dev_app"
  db_username = "dev_admin"
  
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.micro"  # Small and cheap
  
  allocated_storage = 20
  
  # Single-AZ for cost savings
  multi_az = false
  
  # Shorter retention for dev
  backup_retention_period = 1
  
  # Allow deletion without snapshot
  deletion_protection       = false
  skip_final_snapshot      = true
  delete_automated_backups = true
  
  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.security_groups.database_security_group_id]
  
  manage_master_user_password = true
  
  tags = {
    Environment = "development"
  }
}
```

### Pattern 2: Production Database

```hcl
module "prod_database" {
  source = "../../modules/databases/rds"
  
  db_name     = "prod_app"
  db_username = "prod_admin"
  
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.small"
  
  allocated_storage     = 100
  max_allocated_storage = 500  # Autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true
  
  # Multi-AZ for high availability
  multi_az = true
  
  # Long retention for compliance
  backup_retention_period = 30
  
  # Deletion protection
  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "prod-final-${formatdate("YYYY-MM-DD", timestamp())}"
  
  # Monitoring
  performance_insights_enabled = true
  monitoring_interval         = 60
  enabled_cloudwatch_logs_exports = ["postgresql"]
  
  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.security_groups.database_security_group_id]
  
  manage_master_user_password = true
  
  tags = {
    Environment = "production"
    Backup      = "required"
  }
}
```

### Pattern 3: WordPress Database

```hcl
module "wordpress_db" {
  source = "../../modules/databases/rds"
  
  db_name     = "wordpress"
  db_username = "wp_admin"
  
  engine         = "mysql"
  engine_version = "8.0.35"
  instance_class = "db.t3.micro"
  
  allocated_storage = 20
  
  parameter_group_family = "mysql8.0"
  db_parameters = {
    max_connections = "150"
    max_allowed_packet = "67108864"  # 64MB
  }
  
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  
  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.security_groups.database_security_group_id]
  
  manage_master_user_password = true
}
```

### Pattern 4: High-Performance Database

```hcl
module "high_perf_db" {
  source = "../../modules/databases/rds"
  
  db_name     = "analytics"
  db_username = "analytics_admin"
  
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.medium"  # More resources
  
  allocated_storage = 500
  storage_type      = "gp3"
  storage_throughput = 250  # Increased throughput
  
  multi_az = true
  
  # Performance parameters
  parameter_group_family = "postgres15"
  db_parameters = {
    max_connections       = "300"
    shared_buffers       = "1GB"
    effective_cache_size = "3GB"
    work_mem             = "16MB"
    maintenance_work_mem = "256MB"
    random_page_cost     = "1.1"
  }
  
  performance_insights_enabled = true
  monitoring_interval         = 1  # 1-second monitoring
  
  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.security_groups.database_security_group_id]
  
  manage_master_user_password = true
}
```

## Troubleshooting

### Issue: Can't Connect to Database

**Problem**: Connection timeout or "could not connect to server".

**Solutions**:
```bash
# 1. Check security group allows access
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --query 'SecurityGroups[0].IpPermissions'

# Should allow inbound on port 5432 (PostgreSQL) or 3306 (MySQL)
# from application security group

# 2. Check RDS is in correct subnets
aws rds describe-db-instances \
  --db-instance-identifier myapp \
  --query 'DBInstances[0].DBSubnetGroup'

# 3. Verify endpoint is correct
DB_ENDPOINT=$(terraform output -raw db_endpoint)
echo $DB_ENDPOINT

# 4. Test from application server
nc -zv ${DB_ENDPOINT%:*} 5432

# 5. Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier myapp \
  --query 'DBInstances[0].DBInstanceStatus'
```

### Issue: High CPU Usage

**Problem**: Database CPU constantly high.

**Solutions**:
```bash
# 1. Check Performance Insights
# AWS Console → RDS → Performance Insights

# 2. Common causes:
# - Missing indexes
# - Inefficient queries
# - Too many connections
# - Undersized instance

# 3. Enable slow query log
db_parameters = {
  log_min_duration_statement = "1000"  # Log queries > 1 second
}

# 4. Check active connections
SELECT count(*) FROM pg_stat_activity;  # PostgreSQL
SHOW PROCESSLIST;  # MySQL

# 5. Upgrade instance class
instance_class = "db.t3.small"  # Was db.t3.micro
```

### Issue: Storage Full

**Problem**: "disk full" errors.

**Solutions**:
```bash
# 1. Check storage usage
aws rds describe-db-instances \
  --db-instance-identifier myapp \
  --query 'DBInstances[0].[AllocatedStorage,DBInstanceStatus]'

# 2. Enable storage autoscaling
max_allocated_storage = 500  # Allow growth to 500 GB

# 3. Manually increase storage
allocated_storage = 100  # Was 20
# Note: Cannot decrease storage

# 4. Clean up data
# Connect to database and delete old data
DELETE FROM logs WHERE created_at < NOW() - INTERVAL '90 days';
VACUUM FULL;  # PostgreSQL
OPTIMIZE TABLE logs;  # MySQL
```

### Issue: Slow Queries

**Problem**: Queries taking too long.

**Solutions**:
```bash
# 1. Enable Performance Insights
performance_insights_enabled = true

# 2. Check for missing indexes
# PostgreSQL:
SELECT schemaname, tablename, attname, n_distinct, correlation
FROM pg_stats
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n_distinct DESC;

# 3. Analyze slow queries
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

# 4. Optimize parameters
db_parameters = {
  shared_buffers       = "256MB"  # 25% of RAM
  effective_cache_size = "1GB"    # 50-75% of RAM
  work_mem             = "4MB"    # Per operation
}
```

### Issue: Connection Limit Reached

**Problem**: "too many connections" error.

**Solutions**:
```hcl
# 1. Increase max_connections
db_parameters = {
  max_connections = "200"  # Was 100
}

# 2. Use connection pooling in application
# PgBouncer for PostgreSQL
# ProxySQL for MySQL

# 3. Check for connection leaks
# PostgreSQL:
SELECT count(*) FROM pg_stat_activity;
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;
```

## Maintenance

### Backup and Restore

```bash
# Manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier myapp \
  --db-snapshot-identifier myapp-manual-$(date +%Y%m%d)

# List snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier myapp

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier myapp-restored \
  --db-snapshot-identifier myapp-manual-20240101

# Point-in-time restore
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier myapp \
  --target-db-instance-identifier myapp-restored \
  --restore-time 2024-01-01T12:00:00Z
```

### Upgrades

```bash
# Check available versions
aws rds describe-db-engine-versions \
  --engine postgres \
  --engine-version 15.4

# Upgrade (minor version)
auto_minor_version_upgrade = true  # Automatic

# Upgrade (major version)
allow_major_version_upgrade = true
engine_version = "16.1"  # Was 15.4
apply_immediately = false  # Apply during maintenance window
```

### Monitoring Queries

```sql
-- PostgreSQL: Active queries
SELECT pid, usename, state, query, query_start
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;

-- PostgreSQL: Database size
SELECT pg_size_pretty(pg_database_size('myapp'));

-- PostgreSQL: Table sizes
SELECT schemaname, tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
FROM pg_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;

-- MySQL: Active queries
SHOW PROCESSLIST;

-- MySQL: Database size
SELECT table_schema "Database",
  ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) "Size (MB)"
FROM information_schema.TABLES
GROUP BY table_schema;
```

## Best Practices

1. **Always use Secrets Manager** for passwords
2. **Enable Multi-AZ** for production
3. **Enable automated backups** (minimum 7 days)
4. **Enable encryption** at rest and in transit
5. **Use parameter groups** for configuration
6. **Enable Performance Insights** for production
7. **Set deletion protection** for production
8. **Use private subnets** only
9. **Implement connection pooling** in applications
10. **Monitor slow queries** regularly

## References

- [AWS RDS Documentation](https://docs.aws.amazon.com/rds/)
- [RDS Pricing](https://aws.amazon.com/rds/pricing/)
- [PostgreSQL on RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
- [MySQL on RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_MySQL.html)
- [RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
