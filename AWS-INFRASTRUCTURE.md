# AWS Infrastructure Setup Guide
## Django Notes App - Complete Infrastructure as Code

This guide provides detailed AWS infrastructure setup for the Django Notes App with zero-downtime deployment architecture.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Option 1: Manual AWS Setup](#option-1-manual-aws-setup)
4. [Option 2: AWS CLI Setup](#option-2-aws-cli-setup)
5. [Option 3: Terraform Setup](#option-3-terraform-setup)
6. [Network Architecture](#network-architecture)
7. [Cost Estimation](#cost-estimation)
8. [Security Hardening](#security-hardening)

---

## Overview

### Infrastructure Components

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS Cloud                            │
│                                                              │
│  ┌────────────────────────────────────────────────────┐   │
│  │                    VPC (10.0.0.0/16)               │   │
│  │                                                     │   │
│  │  ┌──────────────────┐    ┌──────────────────┐    │   │
│  │  │  Public Subnet   │    │  Public Subnet   │    │   │
│  │  │   us-east-1a     │    │   us-east-1b     │    │   │
│  │  │  10.0.1.0/24     │    │  10.0.2.0/24     │    │   │
│  │  │                  │    │                  │    │   │
│  │  │  ┌────────────┐  │    │  ┌────────────┐  │    │   │
│  │  │  │  EC2-1     │  │    │  │  EC2-2     │  │    │   │
│  │  │  │  Server    │  │    │  │  Server    │  │    │   │
│  │  │  └────────────┘  │    │  └────────────┘  │    │   │
│  │  └──────────────────┘    └──────────────────┘    │   │
│  │           │                        │              │   │
│  │           └────────────┬───────────┘              │   │
│  │                        │                          │   │
│  │                  ┌─────▼──────┐                   │   │
│  │                  │    ALB     │                   │   │
│  │                  └─────┬──────┘                   │   │
│  │                        │                          │   │
│  │  ┌──────────────────┐  │  ┌──────────────────┐  │   │
│  │  │ Private Subnet   │  │  │ Private Subnet   │  │   │
│  │  │   us-east-1a     │  │  │   us-east-1b     │  │   │
│  │  │  10.0.3.0/24     │  │  │  10.0.4.0/24     │  │   │
│  │  │                  │  │  │                  │  │   │
│  │  │  ┌────────────┐  │  │  │  ┌────────────┐  │  │   │
│  │  │  │    RDS     │◄─┘  │  │  │  RDS Read  │  │  │   │
│  │  │  │  Primary   │     │  │  │  Replica   │  │  │   │
│  │  │  └────────────┘     │  │  └────────────┘  │  │   │
│  │  └──────────────────┘  │  └──────────────────┘  │   │
│  └─────────────────────────┼───────────────────────┘   │
│                            │                            │
│                    ┌───────▼────────┐                   │
│                    │ Internet       │                   │
│                    │ Gateway        │                   │
│                    └────────────────┘                   │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
                        Internet
```

### Resource List

| Resource | Quantity | Purpose |
|----------|----------|---------|
| VPC | 1 | Network isolation |
| Public Subnets | 2 | EC2 servers, ALB |
| Private Subnets | 2 | RDS database |
| Internet Gateway | 1 | Internet access |
| NAT Gateway | 2 (optional) | Outbound from private subnets |
| EC2 Instances | 2 | Application servers |
| Application Load Balancer | 1 | Traffic distribution |
| Target Group | 1 | EC2 target management |
| RDS MySQL | 1 | Database |
| Security Groups | 4 | Firewall rules |
| IAM Roles | 2 | Permissions |
| Route Tables | 2-4 | Network routing |

---

## Prerequisites

### Required Tools
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verify installation
aws --version

# Configure AWS credentials
aws configure
```

### Required Permissions

Your AWS user/role needs these permissions:
- EC2 (full access)
- VPC (full access)
- RDS (full access)
- ELB (full access)
- IAM (create roles and policies)
- CloudWatch (read/write)

---

## Option 1: Manual AWS Setup

### Step-by-Step AWS Console Instructions

#### 1. Create VPC

1. Navigate to **VPC Console** → **Create VPC**
2. Settings:
   - Name: `notes-app-vpc`
   - IPv4 CIDR: `10.0.0.0/16`
   - IPv6: No
   - Tenancy: Default
3. Click **Create VPC**

#### 2. Create Subnets

**Public Subnet 1:**
- Name: `notes-app-public-1a`
- VPC: `notes-app-vpc`
- AZ: `us-east-1a`
- CIDR: `10.0.1.0/24`

**Public Subnet 2:**
- Name: `notes-app-public-1b`
- VPC: `notes-app-vpc`
- AZ: `us-east-1b`
- CIDR: `10.0.2.0/24`

**Private Subnet 1:**
- Name: `notes-app-private-1a`
- VPC: `notes-app-vpc`
- AZ: `us-east-1a`
- CIDR: `10.0.3.0/24`

**Private Subnet 2:**
- Name: `notes-app-private-1b`
- VPC: `notes-app-vpc`
- AZ: `us-east-1b`
- CIDR: `10.0.4.0/24`

#### 3. Create and Attach Internet Gateway

1. **VPC** → **Internet Gateways** → **Create**
2. Name: `notes-app-igw`
3. Attach to `notes-app-vpc`

#### 4. Create Route Tables

**Public Route Table:**
1. Create route table: `notes-app-public-rt`
2. Add route: `0.0.0.0/0` → Internet Gateway
3. Associate with public subnets

**Private Route Table:**
1. Create route table: `notes-app-private-rt`
2. Associate with private subnets

#### 5. Create Security Groups

**ALB Security Group:**
```
Name: notes-app-alb-sg
Inbound Rules:
  - HTTP (80) from 0.0.0.0/0
  - HTTPS (443) from 0.0.0.0/0
Outbound Rules:
  - All traffic
```

**EC2 Security Group:**
```
Name: notes-app-ec2-sg
Inbound Rules:
  - SSH (22) from YOUR_IP/32
  - Custom TCP (8000) from notes-app-alb-sg
Outbound Rules:
  - All traffic
```

**RDS Security Group:**
```
Name: notes-app-rds-sg
Inbound Rules:
  - MySQL (3306) from notes-app-ec2-sg
Outbound Rules:
  - None needed
```

#### 6. Create RDS Database

1. **RDS Console** → **Create database**
2. Settings:
   - Engine: MySQL 8.0
   - Template: Production (or Dev/Test)
   - DB instance: `notes-app-db`
   - Master username: `admin`
   - Master password: [Generate secure password]
   - Instance class: `db.t3.micro`
   - Storage: 20 GB SSD
   - Multi-AZ: Yes (for production)
   - VPC: `notes-app-vpc`
   - Subnet group: Create new with private subnets
   - Public access: No
   - Security group: `notes-app-rds-sg`
   - Database name: `notes_db`
3. Create database (takes 5-10 minutes)

#### 7. Create IAM Role for EC2

1. **IAM Console** → **Roles** → **Create role**
2. Trusted entity: AWS service → EC2
3. Permissions:
   - `AmazonEC2ContainerRegistryReadOnly`
   - `CloudWatchAgentServerPolicy`
4. Name: `notes-app-ec2-role`

#### 8. Launch EC2 Instances

**Launch Server 1:**
1. **EC2 Console** → **Launch Instance**
2. Settings:
   - Name: `notes-app-server-1`
   - AMI: Ubuntu Server 22.04 LTS
   - Instance type: `t3.medium`
   - Key pair: Select or create
   - Network: `notes-app-vpc`
   - Subnet: `notes-app-public-1a`
   - Auto-assign public IP: Enable
   - Security group: `notes-app-ec2-sg`
   - IAM role: `notes-app-ec2-role`
   - Storage: 30 GB gp3
   - Advanced → User data: [Paste bootstrap script]
3. Launch instance

**Launch Server 2:**
- Repeat above with:
  - Name: `notes-app-server-2`
  - Subnet: `notes-app-public-1b`

#### 9. Create Application Load Balancer

1. **EC2 Console** → **Load Balancers** → **Create**
2. Type: Application Load Balancer
3. Settings:
   - Name: `notes-app-alb`
   - Scheme: Internet-facing
   - IP type: IPv4
   - VPC: `notes-app-vpc`
   - Subnets: Select both public subnets
   - Security group: `notes-app-alb-sg`
4. Configure Target Group:
   - Name: `notes-app-targets`
   - Target type: Instance
   - Protocol: HTTP
   - Port: 8000
   - Health check path: `/admin/login/`
   - Advanced health check:
     - Interval: 30 seconds
     - Timeout: 5 seconds
     - Healthy threshold: 2
     - Unhealthy threshold: 3
   - Deregistration delay: 30 seconds
5. Register targets: Add both EC2 instances
6. Create load balancer

---

## Option 2: AWS CLI Setup

Complete automation script using AWS CLI:

```bash
#!/bin/bash
# Complete AWS Infrastructure Setup Script

set -e

# Configuration
REGION="us-east-1"
VPC_CIDR="10.0.0.0/16"
PROJECT_NAME="notes-app"

echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --region $REGION \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc}]" \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC Created: $VPC_ID"

# Enable DNS
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support

echo "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --region $REGION \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw}]" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

echo "Creating Subnets..."
# Public Subnet 1
PUBLIC_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ${REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-1a}]" \
  --query 'Subnet.SubnetId' \
  --output text)

# Public Subnet 2
PUBLIC_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone ${REGION}b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-1b}]" \
  --query 'Subnet.SubnetId' \
  --output text)

# Private Subnet 1
PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.3.0/24 \
  --availability-zone ${REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-1a}]" \
  --query 'Subnet.SubnetId' \
  --output text)

# Private Subnet 2
PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.4.0/24 \
  --availability-zone ${REGION}b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-1b}]" \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Creating Route Tables..."
# Public Route Table
PUBLIC_RT=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-rt}]" \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route --route-table-id $PUBLIC_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_1
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_2

echo "Creating Security Groups..."
# ALB Security Group
ALB_SG=$(aws ec2 create-security-group \
  --group-name ${PROJECT_NAME}-alb-sg \
  --description "Security group for ALB" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 443 --cidr 0.0.0.0/0

# EC2 Security Group
EC2_SG=$(aws ec2 create-security-group \
  --group-name ${PROJECT_NAME}-ec2-sg \
  --description "Security group for EC2 instances" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 8000 --source-group $ALB_SG

# RDS Security Group
RDS_SG=$(aws ec2 create-security-group \
  --group-name ${PROJECT_NAME}-rds-sg \
  --description "Security group for RDS" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress --group-id $RDS_SG --protocol tcp --port 3306 --source-group $EC2_SG

echo "Creating DB Subnet Group..."
aws rds create-db-subnet-group \
  --db-subnet-group-name ${PROJECT_NAME}-db-subnet \
  --db-subnet-group-description "Subnet group for RDS" \
  --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2

echo "Creating RDS Instance..."
aws rds create-db-instance \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version 8.0.35 \
  --master-username admin \
  --master-user-password YOUR_SECURE_PASSWORD_HERE \
  --allocated-storage 20 \
  --vpc-security-group-ids $RDS_SG \
  --db-subnet-group-name ${PROJECT_NAME}-db-subnet \
  --backup-retention-period 7 \
  --no-publicly-accessible \
  --db-name notes_db

echo "Creating Target Group..."
TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
  --name ${PROJECT_NAME}-targets \
  --protocol HTTP \
  --port 8000 \
  --vpc-id $VPC_ID \
  --health-check-protocol HTTP \
  --health-check-path /admin/login/ \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Modify deregistration delay
aws elbv2 modify-target-group-attributes \
  --target-group-arn $TARGET_GROUP_ARN \
  --attributes Key=deregistration_delay.timeout_seconds,Value=30

echo "Creating Application Load Balancer..."
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name ${PROJECT_NAME}-alb \
  --subnets $PUBLIC_SUBNET_1 $PUBLIC_SUBNET_2 \
  --security-groups $ALB_SG \
  --scheme internet-facing \
  --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

echo "Creating ALB Listener..."
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN

echo "=========================================="
echo "Infrastructure Created Successfully!"
echo "=========================================="
echo "VPC ID: $VPC_ID"
echo "Public Subnets: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"
echo "Private Subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"
echo "ALB Security Group: $ALB_SG"
echo "EC2 Security Group: $EC2_SG"
echo "RDS Security Group: $RDS_SG"
echo "Target Group ARN: $TARGET_GROUP_ARN"
echo "ALB ARN: $ALB_ARN"
echo "=========================================="
echo "Save these IDs for EC2 instance launch!"
```

Save as `setup-infrastructure.sh` and run:
```bash
chmod +x setup-infrastructure.sh
./setup-infrastructure.sh
```

---

## Option 3: Terraform Setup

Coming soon in `terraform/` directory!

---

## Network Architecture

### IP Address Allocation

| Subnet | CIDR | Available IPs | Purpose |
|--------|------|---------------|---------|
| Public 1a | 10.0.1.0/24 | 251 | EC2 Server 1, NAT Gateway |
| Public 1b | 10.0.2.0/24 | 251 | EC2 Server 2, NAT Gateway |
| Private 1a | 10.0.3.0/24 | 251 | RDS Primary |
| Private 1b | 10.0.4.0/24 | 251 | RDS Standby |

### Security Group Rules Details

**notes-app-alb-sg (ALB)**
```
Inbound:
  Rule 1: Type=HTTP, Port=80, Source=0.0.0.0/0, Description=Public HTTP
  Rule 2: Type=HTTPS, Port=443, Source=0.0.0.0/0, Description=Public HTTPS

Outbound:
  Rule 1: Type=All Traffic, Destination=0.0.0.0/0
```

**notes-app-ec2-sg (Application Servers)**
```
Inbound:
  Rule 1: Type=SSH, Port=22, Source=YOUR_IP/32, Description=SSH access
  Rule 2: Type=Custom TCP, Port=8000, Source=notes-app-alb-sg, Description=App from ALB

Outbound:
  Rule 1: Type=All Traffic, Destination=0.0.0.0/0
```

**notes-app-rds-sg (Database)**
```
Inbound:
  Rule 1: Type=MySQL/Aurora, Port=3306, Source=notes-app-ec2-sg, Description=MySQL from EC2

Outbound:
  None required
```

---

## Cost Estimation

### Monthly Cost Breakdown (US East 1)

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| EC2 (2x t3.medium) | On-Demand | ~$60 |
| RDS MySQL (db.t3.micro) | Single-AZ | ~$15 |
| Application Load Balancer | Standard | ~$20 |
| Data Transfer | 100 GB/month | ~$9 |
| EBS Storage | 60 GB gp3 | ~$5 |
| **Total** | | **~$109/month** |

### Production Configuration

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| EC2 (2x t3.medium) | Reserved 1-year | ~$35 |
| RDS MySQL (db.t3.small) | Multi-AZ | ~$60 |
| Application Load Balancer | Standard | ~$20 |
| Data Transfer | 500 GB/month | ~$40 |
| EBS Storage | 100 GB gp3 | ~$8 |
| CloudWatch | Basic monitoring | ~$10 |
| **Total** | | **~$173/month** |

---

## Security Hardening

### 1. Enable VPC Flow Logs

```bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids $VPC_ID \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs
```

### 2. Enable RDS Encryption

Add to RDS creation:
```bash
--storage-encrypted \
--kms-key-id arn:aws:kms:region:account:key/key-id
```

### 3. Enable ALB Access Logs

```bash
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn $ALB_ARN \
  --attributes Key=access_logs.s3.enabled,Value=true Key=access_logs.s3.bucket,Value=my-alb-logs
```

### 4. Implement AWS WAF (optional)

Protect ALB from common web exploits:
```bash
aws wafv2 create-web-acl \
  --name notes-app-waf \
  --scope REGIONAL \
  --default-action Allow={} \
  --rules ...
```

### 5. Set up AWS Config

Monitor compliance and configuration changes

### 6. Enable GuardDuty

Threat detection service

---

## Next Steps

After infrastructure is created:

1. ✅ Note all resource IDs
2. ✅ Update `.env` file with RDS endpoint
3. ✅ Configure GitHub Secrets
4. ✅ SSH to EC2 instances and run bootstrap script
5. ✅ Test manual deployment
6. ✅ Trigger automated deployment from GitHub

---

**Created**: December 18, 2025  
**Author**: DevOps Team  
**Version**: 1.0.0
