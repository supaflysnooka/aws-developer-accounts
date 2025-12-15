# VPC Networking Module

Creates a complete VPC infrastructure with public, private, and database subnets across multiple availability zones.

## Features

- Multi-AZ VPC with configurable CIDR
- Public subnets with Internet Gateway
- Private subnets with NAT Gateway(s)
- Database subnets with dedicated subnet group
- VPC Flow Logs for network monitoring
- Automatic subnet CIDR calculation
- Cost optimization options (single vs multi-AZ NAT)

## Usage

### Basic Example

```hcl
module "vpc" {
  source = "../../modules/networking/vpc"
  
  vpc_name           = "my-app-vpc"
  vpc_cidr          = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
```

### Production Example

```hcl
module "vpc" {
  source = "../../modules/networking/vpc"
  
  vpc_name           = "production-vpc"
  vpc_cidr          = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  
  # Enable all features
  enable_public_subnets   = true
  enable_private_subnets  = true
  enable_database_subnets = true
  
  # Multi-AZ NAT for high availability
  enable_nat_gateway = true
  single_nat_gateway = false  # One NAT per AZ
  
  # Monitoring
  enable_flow_logs       = true
  flow_logs_retention_days = 30
  
  # Security
  manage_default_security_group = true
  manage_default_network_acl    = true
  
  tags = {
    Environment = "production"
    Project     = "my-app"
  }
}
```

### Development Example (Cost Optimized)

```hcl
module "vpc" {
  source = "../../modules/networking/vpc"
  
  vpc_name           = "dev-vpc"
  vpc_cidr          = "10.1.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  
  # Single NAT Gateway to save costs (~$32/month savings)
  enable_nat_gateway = true
  single_nat_gateway = true
  
  # Optional: disable database subnets if not needed
  enable_database_subnets = false
  
  tags = {
    Environment = "development"
    CostCenter  = "engineering"
  }
}
```

## Subnet Architecture

The module automatically calculates subnet CIDRs:

```
VPC: 10.0.0.0/16
├── Public Subnets (Internet-facing)
│   ├── 10.0.0.0/24   (AZ-a)
│   └── 10.0.1.0/24   (AZ-b)
├── Private Subnets (Application tier)
│   ├── 10.0.10.0/24  (AZ-a)
│   └── 10.0.11.0/24  (AZ-b)
└── Database Subnets (Data tier)
    ├── 10.0.20.0/24  (AZ-a)
    └── 10.0.21.0/24  (AZ-b)
```

Each subnet gets 256 IP addresses (/24).

## Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `vpc_name` | string | Yes | - | Name tag for the VPC |
| `vpc_cidr` | string | No | "10.0.0.0/16" | CIDR block for VPC |
| `availability_zones` | list(string) | Yes | - | List of AZs (minimum 2) |
| `enable_dns_hostnames` | bool | No | true | Enable DNS hostnames |
| `enable_dns_support` | bool | No | true | Enable DNS support |
| `enable_internet_gateway` | bool | No | true | Create Internet Gateway |
| `enable_public_subnets` | bool | No | true | Create public subnets |
| `enable_private_subnets` | bool | No | true | Create private subnets |
| `enable_database_subnets` | bool | No | true | Create database subnets |
| `enable_nat_gateway` | bool | No | true | Create NAT Gateway |
| `single_nat_gateway` | bool | No | true | Use single NAT (cost optimization) |
| `map_public_ip_on_launch` | bool | No | false | Auto-assign public IPs in public subnets |
| `enable_flow_logs` | bool | No | true | Enable VPC Flow Logs |
| `flow_logs_retention_days` | number | No | 30 | CloudWatch log retention |
| `manage_default_security_group` | bool | No | true | Make default SG restrictive |
| `manage_default_network_acl` | bool | No | true | Make default NACL restrictive |
| `tags` | map(string) | No | {} | Tags for all resources |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `vpc_id` | string | VPC ID |
| `vpc_arn` | string | VPC ARN |
| `vpc_cidr_block` | string | VPC CIDR |
| `internet_gateway_id` | string | Internet Gateway ID |
| `public_subnets` | list(string) | Public subnet IDs |
| `private_subnets` | list(string) | Private subnet IDs |
| `database_subnets` | list(string) | Database subnet IDs |
| `database_subnet_group` | string | RDS subnet group name |
| `public_subnet_cidrs` | list(string) | Public subnet CIDRs |
| `private_subnet_cidrs` | list(string) | Private subnet CIDRs |
| `database_subnet_cidrs` | list(string) | Database subnet CIDRs |
| `nat_gateway_ids` | list(string) | NAT Gateway IDs |
| `nat_gateway_public_ips` | list(string) | NAT Gateway public IPs |
| `availability_zones` | list(string) | AZs used |

## Cost Considerations

### NAT Gateway Options

**Single NAT Gateway** (default, recommended for dev):
- Cost: ~$32.85/month + data transfer
- One NAT Gateway in first AZ
- All private subnets route through it
- If NAT fails, all private subnets lose internet access

**Multi-AZ NAT Gateways** (recommended for production):
- Cost: ~$65.70/month (2 AZs) + data transfer
- One NAT Gateway per AZ
- High availability - AZ failure doesn't affect other AZs
- Better for production workloads

### Other Costs

- **VPC**: Free
- **Subnets**: Free
- **Internet Gateway**: Free
- **Route Tables**: Free
- **VPC Flow Logs**: ~$0.50/GB ingested into CloudWatch
- **Elastic IPs**: $3.65/month if not attached to running instance

**Typical Development VPC Cost**: $35-40/month
**Typical Production VPC Cost**: $70-100/month

## Common Patterns

### Pattern 1: Simple Public/Private VPC

```hcl
module "vpc" {
  source = "../../modules/networking/vpc"
  
  vpc_name           = "simple-vpc"
  vpc_cidr          = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  
  enable_database_subnets = false  # Don't need DB tier
}

# Deploy web servers in public subnets
# Deploy app servers in private subnets
```

### Pattern 2: Database-Only VPC

```hcl
module "vpc" {
  source = "../../modules/networking/vpc"
  
  vpc_name           = "db-vpc"
  vpc_cidr          = "10.2.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  
  enable_public_subnets  = false  # No internet-facing resources
  enable_private_subnets = false  # No app tier
  enable_nat_gateway     = false  # No internet access needed
}

# Deploy RDS in database subnets
# Access via VPC peering or PrivateLink
```

### Pattern 3: Multi-Tier Application

```hcl
module "vpc" {
  source = "../../modules/networking/vpc"
  
  vpc_name           = "app-vpc"
  vpc_cidr          = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  
  # All tiers enabled
  enable_public_subnets   = true  # Load balancers
  enable_private_subnets  = true  # Application servers
  enable_database_subnets = true  # Databases
}

# ALB in public subnets
# ECS/EC2 in private subnets
# RDS in database subnets
```

## Security Best Practices

### 1. Use Private Subnets for Applications

```hcl
# Recommended - Application in private subnet
resource "aws_instance" "app" {
  subnet_id = module.vpc.private_subnets[0]
  # Access via ALB in public subnet
}

# Not recommended - Application directly in public subnet
resource "aws_instance" "app" {
  subnet_id = module.vpc.public_subnets[0]
  # Exposed directly to internet
}
```

### 2. Restrict Database Access

```hcl
# Databases should only be in database subnets
resource "aws_db_instance" "main" {
  db_subnet_group_name = module.vpc.database_subnet_group
  # Database subnets have no internet access by default
}
```

### 3. Enable Flow Logs

```hcl
module "vpc" {
  enable_flow_logs = true  # Monitor all network traffic
}
```

### 4. Manage Default Security Group

```hcl
module "vpc" {
  manage_default_security_group = true  # Denies all traffic
}

# Create explicit security groups for each service
# Don't rely on the default security group
```

## Troubleshooting

### Issue: Private Instances Can't Reach Internet

**Problem**: Instances in private subnets can't download packages, reach APIs, etc.

**Solution**: Ensure NAT Gateway is enabled
```hcl
enable_nat_gateway = true
```

Check route table:
```bash
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxxxx"
# Should see route 0.0.0.0/0 → NAT Gateway
```

### Issue: Public Instances Not Getting Public IPs

**Problem**: Instances in public subnets don't get public IPs automatically.

**Solution**: Enable auto-assign public IP
```hcl
map_public_ip_on_launch = true
```

Or assign Elastic IP manually:
```bash
aws ec2 allocate-address
aws ec2 associate-address --instance-id i-xxxxx --allocation-id eipalloc-xxxxx
```

### Issue: RDS Can't Create in Subnet Group

**Problem**: `DBSubnetGroupDoesNotCoverEnoughAZs` error.

**Solution**: Ensure at least 2 AZs
```hcl
availability_zones = ["us-east-1a", "us-east-1b"]  # Minimum 2
```

### Issue: High NAT Gateway Costs

**Problem**: Data transfer costs are high.

**Solutions**:
1. Use VPC Endpoints for AWS services (S3, DynamoDB)
2. Reduce outbound internet traffic
3. Use S3 Gateway Endpoint (free data transfer)

```hcl
# Add S3 gateway endpoint to reduce NAT costs
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.us-east-1.s3"
  route_table_ids = module.vpc.private_route_table_ids
}
```

## Integration Examples

### With Application Load Balancer

```hcl
module "vpc" {
  source = "../../modules/networking/vpc"
  # ... config
}

module "alb" {
  source = "../../modules/networking/alb"
  
  subnet_ids = module.vpc.public_subnets  # ALB in public subnets
  vpc_id     = module.vpc.vpc_id
}
```

### With ECS Service

```hcl
module "ecs" {
  source = "../../modules/containers/ecs-service"
  
  subnet_ids = module.vpc.private_subnets  # ECS in private subnets
  vpc_id     = module.vpc.vpc_id
}
```

### With RDS Database

```hcl
module "database" {
  source = "../../modules/databases/rds"
  
  subnet_ids = module.vpc.database_subnets  # RDS in database subnets
  vpc_id     = module.vpc.vpc_id
}
```

## Advanced Configuration

### Custom Subnet CIDR Ranges

The module automatically calculates CIDRs, but you can create custom subnets:

```hcl
# After creating VPC with this module
resource "aws_subnet" "custom" {
  vpc_id            = module.vpc.vpc_id
  cidr_block        = "10.0.50.0/24"
  availability_zone = "us-east-1a"
}
```

### VPC Peering

```hcl
# Peer two VPCs
resource "aws_vpc_peering_connection" "main" {
  vpc_id        = module.vpc1.vpc_id
  peer_vpc_id   = module.vpc2.vpc_id
  auto_accept   = true
}
```

### Transit Gateway Integration

For connecting multiple VPCs at scale, use Transit Gateway (separate module needed).

## Validation

After creating the VPC, verify:

```bash
# Check VPC
aws ec2 describe-vpcs --vpc-ids $(terraform output -raw vpc_id)

# Check subnets
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Check NAT Gateway status
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Verify flow logs
aws logs describe-log-groups --log-group-name-prefix "/aws/vpc/flowlogs"
```

## References

- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)
- [VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)
- [NAT Gateway Pricing](https://aws.amazon.com/vpc/pricing/)
- [VPC Flow Logs](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html)
