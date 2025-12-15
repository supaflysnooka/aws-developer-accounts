# modules/networking/vpc/main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  # Calculate subnet CIDRs automatically
  az_count = length(var.availability_zones)
  
  # Public subnets: /24 networks (256 IPs each)
  public_subnet_cidrs = [
    for i in range(local.az_count) : 
    cidrsubnet(var.vpc_cidr, 8, i)
  ]
  
  # Private subnets: /24 networks (256 IPs each)
  private_subnet_cidrs = [
    for i in range(local.az_count) : 
    cidrsubnet(var.vpc_cidr, 8, i + 10)
  ]
  
  # Database subnets: /24 networks (256 IPs each)
  database_subnet_cidrs = [
    for i in range(local.az_count) : 
    cidrsubnet(var.vpc_cidr, 8, i + 20)
  ]
  
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "networking/vpc"
  })
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  
  tags = merge(local.common_tags, {
    Name = var.vpc_name
    Type = "vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  count  = var.enable_internet_gateway ? 1 : 0
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-igw"
    Type = "internet-gateway"
  })
}

# Public Subnets
resource "aws_subnet" "public" {
  count = var.enable_public_subnets ? local.az_count : 0
  
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = var.map_public_ip_on_launch
  
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-public-${substr(var.availability_zones[count.index], -1, 1)}"
    Type = "public"
    Tier = "public"
  })
}

# Private Subnets
resource "aws_subnet" "private" {
  count = var.enable_private_subnets ? local.az_count : 0
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-private-${substr(var.availability_zones[count.index], -1, 1)}"
    Type = "private"
    Tier = "private"
  })
}

# Database Subnets
resource "aws_subnet" "database" {
  count = var.enable_database_subnets ? local.az_count : 0
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.database_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-db-${substr(var.availability_zones[count.index], -1, 1)}"
    Type = "database"
    Tier = "database"
  })
}

# Database Subnet Group
resource "aws_db_subnet_group" "main" {
  count = var.enable_database_subnets ? 1 : 0
  
  name       = "${var.vpc_name}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id
  
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-db-subnet-group"
    Type = "db-subnet-group"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0
  
  domain = "vpc"
  depends_on = [aws_internet_gateway.main]
  
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-nat-eip-${count.index + 1}"
    Type = "nat-eip"
  })
}

# NAT Gateways
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0
  
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.main]
  
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-nat-gw-${count.index + 1}"
    Type = "nat-gateway"
  })
}

# Route Tables - Public
resource "aws_route_table" "public" {
  count = var.enable_public_subnets ? 1 : 0
  
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-public-rt"
    Type = "public-route-table"
  })
}

# Route Tables - Private
resource "aws_route_table" "private" {
  count = var.enable_private_subnets ? (var.single_nat_gateway ? 1 : local.az_count) : 0
  
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-private-rt-${count.index + 1}"
    Type = "private-route-table"
  })
}

# Route Tables - Database
resource "aws_route_table" "database" {
  count = var.enable_database_subnets ? 1 : 0
  
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-db-rt"
    Type = "database-route-table"
  })
}

# Routes - Public to Internet Gateway
resource "aws_route" "public_internet_gateway" {
  count = var.enable_public_subnets && var.enable_internet_gateway ? 1 : 0
  
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id
  
  timeouts {
    create = "5m"
  }
}

# Routes - Private to NAT Gateway
resource "aws_route" "private_nat_gateway" {
  count = var.enable_private_subnets && var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0
  
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
  
  timeouts {
    create = "5m"
  }
}

# Route Table Associations - Public
resource "aws_route_table_association" "public" {
  count = var.enable_public_subnets ? local.az_count : 0
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# Route Table Associations - Private
resource "aws_route_table_association" "private" {
  count = var.enable_private_subnets ? local.az_count : 0
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}

# Route Table Associations - Database
resource "aws_route_table_association" "database" {
  count = var.enable_database_subnets ? local.az_count : 0
  
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database[0].id
}

# VPC Flow Logs
resource "aws_flow_log" "vpc" {
  count = var.enable_flow_logs ? 1 : 0
  
  iam_role_arn    = aws_iam_role.flow_log[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-flow-logs"
    Type = "flow-logs"
  })
}

# CloudWatch Log Group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  
  name              = "/aws/vpc/flowlogs/${var.vpc_name}"
  retention_in_days = var.flow_logs_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-flow-logs"
    Type = "log-group"
  })
}

# IAM Role for VPC Flow Logs
resource "aws_iam_role" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0
  
  name = "${var.vpc_name}-flow-logs-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM Policy for VPC Flow Logs
resource "aws_iam_role_policy" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0
  
  name = "${var.vpc_name}-flow-logs-policy"
  role = aws_iam_role.flow_log[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Default Network ACL rules (restrictive)
resource "aws_default_network_acl" "default" {
  count = var.manage_default_network_acl ? 1 : 0
  
  default_network_acl_id = aws_vpc.main.default_network_acl_id
  subnet_ids             = []
  
  # Deny all traffic by default
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-default-nacl"
    Type = "default-network-acl"
  })
}

# Default Security Group (restrictive)
resource "aws_default_security_group" "default" {
  count = var.manage_default_security_group ? 1 : 0
  
  vpc_id = aws_vpc.main.id
  
  # No ingress or egress rules (deny all)
  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-default-sg"
    Type = "default-security-group"
  })
}
