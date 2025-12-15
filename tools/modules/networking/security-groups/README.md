# Security Groups Module

Pre-configured security group patterns for common application architectures. Creates security groups with appropriate ingress/egress rules for web applications, databases, containers, and serverless functions.

## Features

- Pre-configured patterns for common use cases
- Automatic security group chaining (ALB → Backend → Database)
- Custom security groups support
- VPC endpoint security groups
- Bastion host access patterns
- Zero-trust defaults (deny all, allow specific)

## Usage

### Basic Web Application Stack

```hcl
module "security_groups" {
  source = "../../modules/networking/security-groups"
  
  name_prefix = "my-app"
  vpc_id      = module.vpc.vpc_id
  
  # Web tier
  create_web_alb_sg     = true
  create_web_backend_sg = true
  
  # Data tier
  create_database_sg = true
}

# ALB uses web_alb security group
# Backend (ECS/EC2) uses web_backend security group (allows traffic from ALB)
# Database uses database security group (allows traffic from backend)
```

### Complete Example

```hcl
module "security_groups" {
  source = "../../modules/networking/security-groups"
  
  name_prefix = "production"
  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = "10.0.0.0/16"
  
  # Web tier
  create_web_alb_sg     = true
  web_ingress_cidrs     = ["0.0.0.0/0"]  # Public internet
  
  create_web_backend_sg = true
  backend_port          = 8080
  
  # Data tier
  create_database_sg    = true
  enable_mysql          = false  # PostgreSQL only
  
  # Container tier
  create_ecs_sg         = true
  ecs_container_port    = 3000
  
  # Serverless
  create_lambda_sg      = true
  
  tags = {
    Environment = "production"
    Project     = "my-app"
  }
}
```

### Custom Security Groups

```hcl
module "security_groups" {
  source = "../../modules/networking/security-groups"
  
  name_prefix = "app"
  vpc_id      = module.vpc.vpc_id
  
  custom_security_groups = {
    redis = {
      description = "Redis cache security group"
      ingress_rules = [{
        from_port   = 6379
        to_port     = 6379
        protocol    = "tcp"
        cidr_blocks = ["10.0.0.0/16"]
        description = "Redis from VPC"
      }]
      egress_rules = [{
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        description = "All outbound"
      }]
      tags = {
        Service = "redis"
      }
    }
  }
}
```

## Security Group Architecture

**Traffic Flow:**
```
Internet
  ↓ (80/443)
ALB Security Group
  ↓ (8080)
Backend Security Group
  ↓ (5432/3306)
Database Security Group
```

Each tier only accepts traffic from the tier above it.

## Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `name_prefix` | string | Yes | - | Prefix for security group names |
| `vpc_id` | string | Yes | - | VPC ID where security groups will be created |
| `vpc_cidr` | string | No | "10.0.0.0/16" | VPC CIDR for internal access rules |

### Web Application Load Balancer

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_web_alb_sg` | bool | false | Create security group for ALB |
| `web_ingress_cidrs` | list(string) | ["0.0.0.0/0"] | CIDR blocks allowed to access web services |

### Web Backend

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_web_backend_sg` | bool | false | Create security group for backend |
| `backend_port` | number | 8080 | Port for backend application |
| `backend_ingress_rules` | list(object) | [] | Additional ingress rules |

### Database

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_database_sg` | bool | false | Create security group for database |
| `enable_mysql` | bool | false | Enable MySQL port (3306) |
| `database_ingress_rules` | list(object) | [] | Additional ingress rules |

### Lambda

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_lambda_sg` | bool | false | Create security group for Lambda |
| `lambda_ingress_rules` | list(object) | [] | Ingress rules for Lambda |

### ECS

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_ecs_sg` | bool | false | Create security group for ECS |
| `ecs_container_port` | number | 80 | Port for ECS container |
| `ecs_ingress_rules` | list(object) | [] | Additional ingress rules |

### Bastion

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_bastion_sg` | bool | false | Create security group for bastion |
| `bastion_ingress_cidrs` | list(string) | ["0.0.0.0/0"] | CIDR blocks allowed to SSH to bastion |

### VPC Endpoints

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_vpc_endpoints_sg` | bool | false | Create security group for VPC endpoints |

### Custom Security Groups

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `custom_security_groups` | map(object) | {} | Map of custom security groups to create |
| `tags` | map(string) | {} | Tags for all resources |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `web_alb_security_group_id` | string | Web ALB security group ID |
| `web_backend_security_group_id` | string | Web backend security group ID |
| `database_security_group_id` | string | Database security group ID |
| `lambda_security_group_id` | string | Lambda security group ID |
| `ecs_security_group_id` | string | ECS security group ID |
| `bastion_security_group_id` | string | Bastion security group ID |
| `vpc_endpoints_security_group_id` | string | VPC endpoints security group ID |
| `custom_security_group_ids` | map(string) | Map of custom security group IDs |
| `security_groups` | map(object) | Complete map of all security group information |

## Security Best Practices

### Principle of Least Privilege

Only allow the minimum required access:

```hcl
# GOOD - Specific source
ingress {
  from_port       = 5432
  to_port         = 5432
  protocol        = "tcp"
  security_groups = [module.sg.web_backend_security_group_id]
  description     = "PostgreSQL from backend"
}

# BAD - Overly permissive
ingress {
  from_port   = 0
  to_port     = 65535
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "All traffic from anywhere"
}
```

### Security Group Chaining

Reference other security groups instead of CIDR blocks:

```hcl
# GOOD - Security group reference
resource "aws_security_group_rule" "app_to_db" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.sg.database_security_group_id
  source_security_group_id = module.sg.web_backend_security_group_id
}

# BAD - CIDR reference (brittle)
resource "aws_security_group_rule" "app_to_db" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = module.sg.database_security_group_id
  cidr_blocks       = ["10.0.10.0/24", "10.0.11.0/24"]  # App subnets
}
```

### Egress Rules

Be explicit about outbound traffic:

```hcl
# Database tier - no internet access needed
# Module creates database SG with NO egress rules by default

# Application tier - needs internet access
# Module creates backend SG with 0.0.0.0/0 egress
```

### Description Fields

Always include descriptions for auditing:

```hcl
backend_ingress_rules = [{
  from_port   = 9200
  to_port     = 9200
  protocol    = "tcp"
  cidr_blocks = ["10.0.0.0/16"]
  description = "Elasticsearch from VPC"  # Always include
}]
```

## Common Patterns

### Pattern 1: Three-Tier Web Application

```hcl
module "security_groups" {
  source = "../../modules/networking/security-groups"
  
  name_prefix = "webapp"
  vpc_id      = module.vpc.vpc_id
  
  # Public tier (ALB)
  create_web_alb_sg = true
  web_ingress_cidrs = ["0.0.0.0/0"]
  
  # Application tier (ECS/EC2)
  create_web_backend_sg = true
  backend_port          = 8080
  
  # Data tier (RDS)
  create_database_sg = true
}

# Traffic flow: Internet → ALB → Backend → Database
```

### Pattern 2: Microservices with Service Mesh

```hcl
module "security_groups" {
  source = "../../modules/networking/security-groups"
  
  name_prefix = "microservices"
  vpc_id      = module.vpc.vpc_id
  
  create_ecs_sg = true
  
  # Allow service-to-service communication
  ecs_ingress_rules = [{
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [module.security_groups.ecs_security_group_id]
    description     = "Service mesh communication"
  }]
}
```

### Pattern 3: Lambda with RDS Access

```hcl
module "security_groups" {
  source = "../../modules/networking/security-groups"
  
  name_prefix = "serverless"
  vpc_id      = module.vpc.vpc_id
  
  create_lambda_sg   = true
  create_database_sg = true
}

# Add rule for Lambda → Database
resource "aws_security_group_rule" "lambda_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.security_groups.database_security_group_id
  source_security_group_id = module.security_groups.lambda_security_group_id
}
```

### Pattern 4: Bastion Host Access

```hcl
module "security_groups" {
  source = "../../modules/networking/security-groups"
  
  name_prefix = "secure"
  vpc_id      = module.vpc.vpc_id
  
  # Bastion in public subnet
  create_bastion_sg     = true
  bastion_ingress_cidrs = ["203.0.113.0/24"]  # Office IP only
  
  # Backend accessible from bastion
  create_web_backend_sg = true
  backend_ingress_rules = [{
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [module.security_groups.bastion_security_group_id]
    description     = "SSH from bastion"
  }]
}
```

## Troubleshooting

### Connection Timeouts

**Problem**: Application can't connect to database despite being in same VPC.

**Solution**: Check security group rules
```bash
# Verify database security group allows backend
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw database_security_group_id)

# Look for ingress rule from backend security group on port 5432/3306
```

### Security Group Dependency Cycles

**Problem**: Terraform error about circular dependencies.

**Solution**: Use separate `aws_security_group_rule` resources:
```hcl
# Instead of inline rules, use separate resources
resource "aws_security_group_rule" "backend_to_db" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.sg.database_security_group_id
  source_security_group_id = module.sg.web_backend_security_group_id
}
```

### Too Many Rules in One Group

**Problem**: Hitting 60-rule limit per security group.

**Solution**: Split into multiple security groups or use prefix lists:
```hcl
# Instead of many CIDR rules, use prefix list
resource "aws_ec2_managed_prefix_list" "office_ips" {
  name           = "office-ip-ranges"
  address_family = "IPv4"
  max_entries    = 100
  
  entry {
    cidr        = "203.0.113.0/24"
    description = "Office 1"
  }
  # ... more entries
}
```

### Port Already in Use

**Problem**: Multiple security groups allowing same port causing confusion.

**Solution**: Be explicit about which security group each resource uses:
```hcl
# Each resource uses specific security group
resource "aws_lb" "main" {
  security_groups = [module.sg.web_alb_security_group_id]  # Only ALB SG
}

resource "aws_ecs_service" "app" {
  network_configuration {
    security_groups = [module.sg.web_backend_security_group_id]  # Only backend SG
  }
}
```

## Integration Examples

### With Application Load Balancer

```hcl
module "security_groups" {
  source = "../../modules/networking/security-groups"
  
  name_prefix       = "app"
  vpc_id            = module.vpc.vpc_id
  create_web_alb_sg = true
}

module "alb" {
  source = "../../modules/networking/alb"
  
  security_group_ids = [module.security_groups.web_alb_security_group_id]
  # ...
}
```

### With ECS Service

```hcl
module "security_groups" {
  source = "../../modules/networking/security-groups"
  
  name_prefix         = "app"
  vpc_id              = module.vpc.vpc_id
  create_ecs_sg       = true
  create_web_alb_sg   = true
  ecs_container_port  = 3000
}

module "ecs" {
  source = "../../modules/containers/ecs-service"
  
  security_group_ids = [module.security_groups.ecs_security_group_id]
  # ...
}
```

### With RDS Database

```hcl
module "security_groups" {
  source = "../../modules/networking/security-groups"
  
  name_prefix        = "app"
  vpc_id             = module.vpc.vpc_id
  create_database_sg = true
  create_ecs_sg      = true
}

module "database" {
  source = "../../modules/databases/rds"
  
  vpc_security_group_ids = [module.security_groups.database_security_group_id]
  # ...
}
```

## Validation

Verify security groups are configured correctly:

```bash
# List all security groups in VPC
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Check specific security group rules
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw web_alb_security_group_id) \
  --query 'SecurityGroups[0].IpPermissions'

# Test connectivity (from instance in backend SG to database)
nc -zv database-endpoint 5432
```

## References

- [AWS Security Groups Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)
- [Security Group Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)
- [Security Group Rules Reference](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/security-group-rules-reference.html)
