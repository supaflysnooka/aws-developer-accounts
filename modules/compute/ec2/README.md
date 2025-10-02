# EC2 Module

Creates Amazon EC2 instances with automated IAM configuration, EBS volumes, monitoring, and CloudWatch alarms. Optimized for cost-effective development and testing.

## Features

- **Cost-Optimized Types**: Restricted to t3/t4g instance types
- **Auto-configured IAM**: Optional IAM instance profile creation
- **EBS Encryption**: Encrypted root and additional volumes
- **Elastic IPs**: Optional static IP addresses
- **CloudWatch Monitoring**: Detailed monitoring and alarms
- **User Data**: Bootstrap scripts for initialization
- **IMDSv2**: Required by default for enhanced security

## Usage

### Basic Example

```hcl
module "ec2" {
  source = "../../modules/compute/ec2"
  
  instance_name = "web-server"
  instance_type = "t3.micro"
  
  subnet_ids         = [module.vpc.public_subnets[0]]
  security_group_ids = [module.security_groups.web_backend_security_group_id]
  
  key_name = "my-ssh-key"
}
```

### Complete Production Example

```hcl
module "app_servers" {
  source = "../../modules/compute/ec2"
  
  # Instance Configuration
  instance_name  = "app-server"
  instance_count = 2  # Create 2 instances
  instance_type  = "t3.small"
  
  # AMI (auto-selects latest Amazon Linux 2023 if not specified)
  ami_filter_name = "al2023-ami-*-x86_64"
  architecture    = "x86_64"
  
  # Networking
  subnet_ids                  = module.vpc.private_subnets
  security_group_ids          = [module.security_groups.web_backend_security_group_id]
  associate_public_ip_address = false
  
  # SSH Access
  key_name = aws_key_pair.deployer.key_name
  
  # Storage
  root_volume_type = "gp3"
  root_volume_size = 30  # GB
  root_volume_encrypted = true
  
  # Additional EBS volumes
  ebs_volumes = [
    {
      device_name           = "/dev/sdf"
      volume_type           = "gp3"
      volume_size           = 100
      encrypted             = true
      delete_on_termination = true
    }
  ]
  
  # IAM
  create_iam_instance_profile = true
  iam_managed_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
  
  # User Data
  user_data = templatefile("${path.module}/user-data.sh", {
    environment = "production"
    app_version = "1.2.3"
  })
  
  # Monitoring
  enable_detailed_monitoring = true
  enable_cloudwatch_logs    = true
  log_retention_days        = 30
  
  create_cloudwatch_alarms = true
  cpu_alarm_threshold     = 80
  alarm_actions          = [aws_sns_topic.alerts.arn]
  
  # Protection
  enable_termination_protection = true
  
  tags = {
    Environment = "production"
    Application = "api"
  }
}
```

### With Elastic IP

```hcl
module "bastion" {
  source = "../../modules/compute/ec2"
  
  instance_name = "bastion"
  instance_type = "t3.micro"
  
  subnet_ids         = [module.vpc.public_subnets[0]]
  security_group_ids = [module.security_groups.bastion_security_group_id]
  
  # Assign Elastic IP
  create_eip = true
  
  key_name = "bastion-key"
}

output "bastion_ip" {
  value = module.bastion.elastic_ips[0]
}
```

### Auto-Scaling with User Data

```hcl
module "web_servers" {
  source = "../../modules/compute/ec2"
  
  instance_name  = "web"
  instance_count = 3
  instance_type  = "t3.micro"
  
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [module.security_groups.web_backend_security_group_id]
  
  # Bootstrap script
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html
              EOF
  
  user_data_replace_on_change = true  # Replace instance when user data changes
}
```

## Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `instance_name` | string | Name tag for instances |
| `subnet_ids` | list(string) | Subnet IDs for instance placement |
| `security_group_ids` | list(string) | Security group IDs |

### Instance Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `instance_count` | number | 1 | Number of instances to create |
| `instance_type` | string | "t3.micro" | EC2 instance type (t3/t4g only) |

**Allowed Instance Types** (enforced by validation):
- t3.nano, t3.micro, t3.small, t3.medium
- t4g.nano, t4g.micro, t4g.small, t4g.medium (ARM-based, ~20% cheaper)

### AMI Selection

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ami_id` | string | null | Specific AMI ID (overrides filter) |
| `ami_filter_name` | string | "al2023-ami-*-x86_64" | AMI filter pattern |
| `ami_owner` | string | "amazon" | AMI owner account ID |
| `architecture` | string | "x86_64" | CPU architecture (x86_64 or arm64) |

### Networking

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `associate_public_ip_address` | bool | false | Auto-assign public IP |
| `create_eip` | bool | false | Create and associate Elastic IP |

### Storage

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `root_volume_type` | string | "gp3" | Root volume type (gp3, gp2, io1, io2) |
| `root_volume_size` | number | 20 | Root volume size in GB |
| `root_volume_delete_on_termination` | bool | true | Delete volume on termination |
| `root_volume_encrypted` | bool | true | Encrypt root volume |
| `kms_key_id` | string | null | KMS key for encryption |
| `ebs_volumes` | list(object) | [] | Additional EBS volumes |

### Access

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `key_name` | string | null | SSH key pair name |
| `user_data` | string | null | User data script |
| `user_data_replace_on_change` | bool | false | Replace instance when user data changes |

### IAM

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_iam_instance_profile` | bool | false | Create IAM instance profile |
| `iam_instance_profile_name` | string | null | Existing instance profile name |
| `iam_managed_policy_arns` | list(string) | [] | Managed policy ARNs to attach |
| `iam_inline_policies` | map(string) | {} | Inline policies (name → policy JSON) |

### Monitoring

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_detailed_monitoring` | bool | false | Enable detailed (1-min) monitoring |
| `enable_cloudwatch_logs` | bool | false | Create log group |
| `log_retention_days` | number | 30 | Log retention in days |
| `create_cloudwatch_alarms` | bool | false | Create CloudWatch alarms |
| `cpu_alarm_threshold` | number | 80 | CPU utilization alarm threshold |
| `alarm_actions` | list(string) | [] | SNS topic ARNs for alarms |

### Security

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `require_imdsv2` | bool | true | Require IMDSv2 for metadata |
| `metadata_hop_limit` | number | 1 | Metadata service hop limit |
| `enable_termination_protection` | bool | false | Enable termination protection |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `instance_ids` | list(string) | List of instance IDs |
| `instance_arns` | list(string) | List of instance ARNs |
| `private_ips` | list(string) | Private IP addresses |
| `public_ips` | list(string) | Public IP addresses (if assigned) |
| `elastic_ips` | list(string) | Elastic IPs (if created) |
| `iam_role_arn` | string | IAM role ARN (if created) |
| `instance_profile_arn` | string | Instance profile ARN (if created) |

## Cost Considerations

**EC2 Pricing** (us-east-1, on-demand, as of 2024):

| Instance Type | vCPU | Memory | Hourly | Monthly* |
|---------------|------|--------|--------|----------|
| t3.nano | 2 | 0.5 GB | $0.0052 | $3.80 |
| t3.micro | 2 | 1 GB | $0.0104 | $7.59 |
| t3.small | 2 | 2 GB | $0.0208 | $15.18 |
| t3.medium | 2 | 4 GB | $0.0416 | $30.37 |
| t4g.nano | 2 | 0.5 GB | $0.0042 | $3.07 |
| t4g.micro | 2 | 1 GB | $0.0084 | $6.13 |
| t4g.small | 2 | 2 GB | $0.0168 | $12.26 |
| t4g.medium | 2 | 4 GB | $0.0336 | $24.53 |

*Monthly = 730 hours

**Additional Costs**:
- **EBS gp3**: $0.08/GB/month
- **EBS gp2**: $0.10/GB/month
- **Elastic IP**: $3.65/month (when not attached to running instance)
- **Data Transfer Out**: $0.09/GB to internet

**Cost Optimization**:
1. Use t4g (ARM) instances for 20% savings
2. Stop instances when not in use (EBS charges continue)
3. Use Reserved Instances for long-term workloads (up to 72% discount)
4. Right-size instances based on CloudWatch metrics
5. Use gp3 instead of gp2 for EBS

## Common Patterns

### Pattern 1: Web Server

```hcl
module "web_server" {
  source = "../../modules/compute/ec2"
  
  instance_name = "web"
  instance_type = "t3.small"
  
  subnet_ids                  = module.vpc.public_subnets
  security_group_ids          = [module.security_groups.web_backend_security_group_id]
  associate_public_ip_address = true
  
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php
              systemctl start httpd
              systemctl enable httpd
              EOF
  
  key_name = "web-server-key"
}
```

### Pattern 2: Database Server

```hcl
module "database_server" {
  source = "../../modules/compute/ec2"
  
  instance_name = "postgres"
  instance_type = "t3.medium"
  
  subnet_ids         = module.vpc.database_subnets
  security_group_ids = [module.security_groups.database_security_group_id]
  
  # Larger root volume for database
  root_volume_size = 50
  
  # Additional data volume
  ebs_volumes = [{
    device_name           = "/dev/sdf"
    volume_type           = "gp3"
    volume_size           = 200
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = false  # Keep data if instance replaced
  }]
  
  # Database initialization
  user_data = <<-EOF
              #!/bin/bash
              yum install -y postgresql15-server
              postgresql-setup --initdb
              systemctl start postgresql
              systemctl enable postgresql
              EOF
  
  # Protect production database
  enable_termination_protection = true
  
  key_name = "db-admin-key"
}
```

### Pattern 3: Bastion Host

```hcl
module "bastion" {
  source = "../../modules/compute/ec2"
  
  instance_name = "bastion"
  instance_type = "t3.micro"  # Small instance is sufficient
  
  subnet_ids                  = [module.vpc.public_subnets[0]]
  security_group_ids          = [module.security_groups.bastion_security_group_id]
  associate_public_ip_address = true
  create_eip                  = true  # Static IP
  
  # SSM Session Manager (no SSH key needed)
  create_iam_instance_profile = true
  iam_managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
  
  # Minimal storage
  root_volume_size = 10
}

# Access via SSM (no SSH needed)
# aws ssm start-session --target <instance-id>
```

### Pattern 4: Application Server with Auto-Recovery

```hcl
module "app_server" {
  source = "../../modules/compute/ec2"
  
  instance_name = "app"
  instance_type = "t3.small"
  
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [module.security_groups.web_backend_security_group_id]
  
  # IAM for application
  create_iam_instance_profile = true
  iam_managed_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
  iam_inline_policies = {
    s3_access = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::my-app-bucket/*"
      }]
    })
  }
  
  # Monitoring and alerts
  enable_detailed_monitoring = true
  create_cloudwatch_alarms   = true
  cpu_alarm_threshold        = 80
  alarm_actions             = [aws_sns_topic.alerts.arn]
  
  # Auto-recovery on system failures
  # (AWS automatically recovers if status checks fail)
}
```

### Pattern 5: Development Workstation

```hcl
module "dev_workstation" {
  source = "../../modules/compute/ec2"
  
  instance_name = "dev-workstation"
  instance_type = "t3.medium"  # More resources for development
  
  subnet_ids         = [module.vpc.public_subnets[0]]
  security_group_ids = [aws_security_group.dev_workstation.id]
  create_eip        = true
  
  # Larger storage for development
  root_volume_size = 100
  
  # Development tools
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y git docker nodejs python3
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user
              EOF
  
  key_name = "developer-key"
}
```

## User Data Examples

### Example 1: Web Server Setup

```bash
#!/bin/bash
set -e

# Update system
yum update -y

# Install web server
yum install -y httpd mod_ssl

# Configure firewall
systemctl start httpd
systemctl enable httpd

# Deploy application
aws s3 cp s3://my-bucket/app.zip /tmp/
unzip /tmp/app.zip -d /var/www/html/

# Signal CloudFormation/Terraform
/opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource Instance --region ${AWS::Region}
```

### Example 2: Docker Host

```bash
#!/bin/bash
set -e

# Install Docker
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Pull and run application
docker pull nginx:latest
docker run -d -p 80:80 nginx
```

### Example 3: CloudWatch Agent

```bash
#!/bin/bash
set -e

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
{
  "metrics": {
    "namespace": "CustomApp",
    "metrics_collected": {
      "mem": {
        "measurement": [{"name": "mem_used_percent"}]
      },
      "disk": {
        "measurement": [{"name": "disk_used_percent"}],
        "resources": ["*"]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/application.log",
            "log_group_name": "/aws/ec2/application",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CWCONFIG

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
```

## Troubleshooting

### Issue: Instance Won't Start

**Problem**: Instance state is "pending" for a long time or fails to start.

**Debugging**:
```bash
# Check instance status
aws ec2 describe-instances --instance-ids i-1234567890abcdef0

# Check system logs
aws ec2 get-console-output --instance-id i-1234567890abcdef0

# Common issues:
# - User data script error
# - Insufficient IAM permissions
# - Subnet has no available IPs
# - Instance type not available in AZ
```

**Solutions**:
```bash
# Fix user data (add error handling)
#!/bin/bash
set -e  # Exit on error
set -x  # Print commands (for debugging)

# Try different availability zone
subnet_ids = [module.vpc.private_subnets[1]]  # Try second subnet

# Check capacity
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters Name=instance-type,Values=t3.micro \
  --region us-east-1
```

### Issue: Can't SSH to Instance

**Problem**: Connection times out or "Connection refused".

**Solutions**:
```bash
# 1. Check security group allows SSH
aws ec2 describe-security-groups --group-ids sg-xxxxx

# Should have rule:
# Type: SSH, Protocol: TCP, Port: 22, Source: <your-ip>/32

# 2. Check instance has public IP (if in public subnet)
aws ec2 describe-instances --instance-ids i-xxxxx \
  --query 'Reservations[0].Instances[0].PublicIpAddress'

# 3. Check network ACLs
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=vpc-xxxxx"

# 4. Verify key pair
ssh -i ~/.ssh/my-key.pem ec2-user@<public-ip>
chmod 400 ~/.ssh/my-key.pem  # Fix permissions if needed

# 5. Use Session Manager instead (no SSH needed)
aws ssm start-session --target i-xxxxx
```

### Issue: High CPU Usage

**Problem**: Instance constantly at 100% CPU.

**Solutions**:
```bash
# Check what's using CPU
aws ssm send-command \
  --instance-ids i-xxxxx \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["top -b -n 1 | head -20"]'

# Common causes:
# 1. Application needs more resources → upgrade instance type
# 2. Runaway process → restart application
# 3. DDoS attack → check CloudWatch metrics, update security groups

# Upgrade instance type
instance_type = "t3.small"  # Was t3.micro

# Or add more instances and load balance
instance_count = 3
```

### Issue: Out of Disk Space

**Problem**: Application fails with "No space left on device".

**Solutions**:
```bash
# Check disk usage
aws ssm start-session --target i-xxxxx
df -h

# Increase root volume size
root_volume_size = 50  # Was 20

# Or add additional volume
ebs_volumes = [{
  device_name = "/dev/sdf"
  volume_size = 100
  encrypted   = true
}]

# Then mount it:
# sudo mkfs -t ext4 /dev/xvdf
# sudo mkdir /data
# sudo mount /dev/xvdf /data
```

### Issue: Instance Terminated Unexpectedly

**Problem**: Instance terminated without user action.

**Debugging**:
```bash
# Check CloudWatch events
aws ec2 describe-instances \
  --instance-ids i-xxxxx \
  --query 'Reservations[0].Instances[0].StateTransitionReason'

# Possible reasons:
# - User-initiated
# - Spot instance interruption
# - Auto-scaling action
# - System maintenance
# - Failed health check

# Prevent accidental termination
enable_termination_protection = true
```

## Monitoring

### CloudWatch Metrics

Built-in metrics (no agent):
- **CPUUtilization**: Percentage
- **DiskReadOps/DiskWriteOps**: IOPS
- **NetworkIn/NetworkOut**: Bytes
- **StatusCheckFailed**: 0 or 1

With CloudWatch agent:
- **Memory utilization**
- **Disk utilization**
- **Process metrics**
- **Custom application metrics**

### Sample Alarms

```hcl
# High CPU alarm
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.instance_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "CPU utilization is too high"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    InstanceId = module.ec2.instance_ids[0]
  }
}

# Status check alarm (auto-recovery)
resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "${var.instance_name}-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed_System"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "System status check failed - will auto-recover"
  alarm_actions       = [
    "arn:aws:automate:us-east-1:ec2:recover",  # Auto-recovery
    aws_sns_topic.alerts.arn
  ]
  
  dimensions = {
    InstanceId = module.ec2.instance_ids[0]
  }
}
```

## Best Practices

### 1. Use IAM Roles, Not Access Keys

```hcl
# Recommended - Use IAM role
create_iam_instance_profile = true
iam_managed_policy_arns = [
  "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
]

# Not Recommended - Don't hardcode credentials in user data
user_data = <<-EOF
  export AWS_ACCESS_KEY_ID=AKIA...
  export AWS_SECRET_ACCESS_KEY=...
EOF
```

### 2. Enable IMDSv2

```hcl
# Already enabled by default
require_imdsv2 = true

# This prevents SSRF attacks that access metadata
```

### 3. Encrypt Everything

```hcl
root_volume_encrypted = true

ebs_volumes = [{
  encrypted = true
  kms_key_id = aws_kms_key.ebs.arn
}]
```

### 4. Use Private Subnets

```hcl
# Recommended - Application in private subnet
subnet_ids = module.vpc.private_subnets

# Not recommended - Application directly exposed
subnet_ids = module.vpc.public_subnets
associate_public_ip_address = true
```

### 5. Implement Backups

```hcl
# AMI backups via Data Lifecycle Manager
resource "aws_dlm_lifecycle_policy" "instance_backup" {
  description        = "Daily instance backup"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"
  
  policy_details {
    resource_types = ["INSTANCE"]
    
    schedule {
      name = "Daily backup"
      
      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }
      
      retain_rule {
        count = 7  # Keep 7 days
      }
      
      tags_to_add = {
        SnapshotType = "DailyBackup"
      }
    }
    
    target_tags = {
      Backup = "true"
    }
  }
}
```

### 6. Use Systems Manager Session Manager

```hcl
# No SSH keys needed, access via SSM
create_iam_instance_profile = true
iam_managed_policy_arns = [
  "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
]

# Access:
# aws ssm start-session --target i-xxxxx
```

## Integration Examples

### With Auto Scaling Group

```hcl
# Launch template (instead of direct EC2)
resource "aws_launch_template" "app" {
  name_prefix   = "app-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.small"
  
  iam_instance_profile {
    arn = module.ec2.instance_profile_arn
  }
  
  vpc_security_group_ids = [module.security_groups.web_backend_security_group_id]
  
  user_data = base64encode(templatefile("user-data.sh", {}))
  
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      encrypted   = true
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "app-asg"
  vpc_zone_identifier = module.vpc.private_subnets
  target_group_arns   = [module.alb.default_target_group_arn]
  health_check_type   = "ELB"
  
  min_size         = 2
  max_size         = 10
  desired_capacity = 3
  
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
}
```

### With Application Load Balancer

```hcl
module "web_servers" {
  source = "../../modules/compute/ec2"
  
  instance_count = 2
  instance_name  = "web"
  instance_type  = "t3.small"
  
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [module.security_groups.web_backend_security_group_id]
}

# Register with ALB target group
resource "aws_lb_target_group_attachment" "web" {
  count = length(module.web_servers.instance_ids)
  
  target_group_arn = module.alb.default_target_group_arn
  target_id        = module.web_servers.instance_ids[count.index]
  port             = 80
}
```

## References

- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [EC2 Pricing](https://aws.amazon.com/ec2/pricing/)
- [Instance Types](https://aws.amazon.com/ec2/instance-types/)
- [User Data Scripts](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
- [Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
