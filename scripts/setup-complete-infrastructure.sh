
#!/bin/bash

################################################################################
# Complete AWS Infrastructure Setup Script
# This script creates everything needed for zero-downtime deployment
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
PROJECT_NAME="django-notes"
REGION="us-east-1"
VPC_CIDR="10.0.0.0/16"
DB_PASSWORD="NotesApp2025SecurePass"
KEY_NAME="django-notes-key"

log_info "======================================"
log_info "AWS Infrastructure Setup"
log_info "Project: $PROJECT_NAME"
log_info "Region: $REGION"
log_info "======================================"
echo ""

# Create SSH Key Pair
log_info "Step 1: Creating SSH Key Pair..."
if [ ! -f ~/.ssh/${KEY_NAME}.pem ]; then
    /usr/local/bin/aws ec2 create-key-pair \
        --key-name ${KEY_NAME} \
        --region ${REGION} \
        --query 'KeyMaterial' \
        --output text > ~/.ssh/${KEY_NAME}.pem
    chmod 400 ~/.ssh/${KEY_NAME}.pem
    log_success "SSH key created: ~/.ssh/${KEY_NAME}.pem"
else
    log_info "SSH key already exists"
fi

# Get Ubuntu AMI
log_info "Step 2: Finding Ubuntu 22.04 AMI..."
AMI_ID=$(/usr/local/bin/aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text \
    --region ${REGION})
log_success "Found AMI: $AMI_ID"

# Create VPC
log_info "Step 3: Creating VPC..."
VPC_ID=$(/usr/local/bin/aws ec2 create-vpc \
    --cidr-block ${VPC_CIDR} \
    --region ${REGION} \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc}]" \
    --query 'Vpc.VpcId' \
    --output text)
log_success "VPC created: $VPC_ID"

# Enable DNS
/usr/local/bin/aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames --region ${REGION}
/usr/local/bin/aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support --region ${REGION}

# Create Internet Gateway
log_info "Step 4: Creating Internet Gateway..."
IGW_ID=$(/usr/local/bin/aws ec2 create-internet-gateway \
    --region ${REGION} \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw}]" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)
/usr/local/bin/aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID --region ${REGION}
log_success "Internet Gateway created: $IGW_ID"

# Create Subnets
log_info "Step 5: Creating Subnets..."
PUBLIC_SUBNET_1=$(/usr/local/bin/aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone ${REGION}a \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-1a}]" \
    --region ${REGION} \
    --query 'Subnet.SubnetId' \
    --output text)

PUBLIC_SUBNET_2=$(/usr/local/bin/aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone ${REGION}b \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-1b}]" \
    --region ${REGION} \
    --query 'Subnet.SubnetId' \
    --output text)

# Enable auto-assign public IP
/usr/local/bin/aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_1 --map-public-ip-on-launch --region ${REGION}
/usr/local/bin/aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_2 --map-public-ip-on-launch --region ${REGION}

log_success "Subnets created: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"

# Create Route Table
log_info "Step 6: Creating Route Table..."
PUBLIC_RT=$(/usr/local/bin/aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-rt}]" \
    --region ${REGION} \
    --query 'RouteTable.RouteTableId' \
    --output text)

/usr/local/bin/aws ec2 create-route --route-table-id $PUBLIC_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region ${REGION}
/usr/local/bin/aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_1 --region ${REGION}
/usr/local/bin/aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_2 --region ${REGION}
log_success "Route table configured"

# Create Security Groups
log_info "Step 7: Creating Security Groups..."

# ALB Security Group
ALB_SG=$(/usr/local/bin/aws ec2 create-security-group \
    --group-name ${PROJECT_NAME}-alb-sg \
    --description "Security group for ALB" \
    --vpc-id $VPC_ID \
    --region ${REGION} \
    --query 'GroupId' \
    --output text)

/usr/local/bin/aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0 --region ${REGION}
/usr/local/bin/aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 443 --cidr 0.0.0.0/0 --region ${REGION}

# EC2 Security Group
EC2_SG=$(/usr/local/bin/aws ec2 create-security-group \
    --group-name ${PROJECT_NAME}-ec2-sg \
    --description "Security group for EC2" \
    --vpc-id $VPC_ID \
    --region ${REGION} \
    --query 'GroupId' \
    --output text)

/usr/local/bin/aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 22 --cidr 0.0.0.0/0 --region ${REGION}
/usr/local/bin/aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 8000 --source-group $ALB_SG --region ${REGION}
/usr/local/bin/aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol -1 --source-group $EC2_SG --region ${REGION}

log_success "Security groups created: ALB=$ALB_SG, EC2=$EC2_SG"

# Launch EC2 Instances
log_info "Step 8: Launching EC2 instances (this takes 2-3 minutes)..."

INSTANCE_1=$(/usr/local/bin/aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t2.micro \
    --key-name ${KEY_NAME} \
    --security-group-ids $EC2_SG \
    --subnet-id $PUBLIC_SUBNET_1 \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-server-1}]" \
    --region ${REGION} \
    --query 'Instances[0].InstanceId' \
    --output text)

INSTANCE_2=$(/usr/local/bin/aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t2.micro \
    --key-name ${KEY_NAME} \
    --security-group-ids $EC2_SG \
    --subnet-id $PUBLIC_SUBNET_2 \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-server-2}]" \
    --region ${REGION} \
    --query 'Instances[0].InstanceId' \
    --output text)

log_success "Instances launched: $INSTANCE_1, $INSTANCE_2"
log_info "Waiting for instances to be running..."

/usr/local/bin/aws ec2 wait instance-running --instance-ids $INSTANCE_1 $INSTANCE_2 --region ${REGION}

# Get Instance IPs
INSTANCE_1_IP=$(/usr/local/bin/aws ec2 describe-instances \
    --instance-ids $INSTANCE_1 \
    --region ${REGION} \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

INSTANCE_2_IP=$(/usr/local/bin/aws ec2 describe-instances \
    --instance-ids $INSTANCE_2 \
    --region ${REGION} \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

log_success "Instance 1 IP: $INSTANCE_1_IP"
log_success "Instance 2 IP: $INSTANCE_2_IP"

# Create Target Group
log_info "Step 9: Creating Application Load Balancer..."

TARGET_GROUP_ARN=$(/usr/local/bin/aws elbv2 create-target-group \
    --name ${PROJECT_NAME}-tg \
    --protocol HTTP \
    --port 8000 \
    --vpc-id $VPC_ID \
    --health-check-protocol HTTP \
    --health-check-path /admin/login/ \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --region ${REGION} \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

# Set deregistration delay
/usr/local/bin/aws elbv2 modify-target-group-attributes \
    --target-group-arn $TARGET_GROUP_ARN \
    --attributes Key=deregistration_delay.timeout_seconds,Value=30 \
    --region ${REGION}

# Register targets
/usr/local/bin/aws elbv2 register-targets \
    --target-group-arn $TARGET_GROUP_ARN \
    --targets Id=$INSTANCE_1 Id=$INSTANCE_2 \
    --region ${REGION}

log_success "Target group created"

# Create ALB
ALB_ARN=$(/usr/local/bin/aws elbv2 create-load-balancer \
    --name ${PROJECT_NAME}-alb \
    --subnets $PUBLIC_SUBNET_1 $PUBLIC_SUBNET_2 \
    --security-groups $ALB_SG \
    --scheme internet-facing \
    --type application \
    --region ${REGION} \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

ALB_DNS=$(/usr/local/bin/aws elbv2 describe-load-balancers \
    --load-balancer-arns $ALB_ARN \
    --region ${REGION} \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

# Create Listener
/usr/local/bin/aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
    --region ${REGION}

log_success "ALB created: $ALB_DNS"

# Save configuration
log_info "Step 10: Saving infrastructure details..."
cat > ~/infrastructure-details.txt << EOF
========================================
AWS Infrastructure Details
Created: $(date)
========================================

VPC ID: $VPC_ID
Internet Gateway: $IGW_ID
Public Subnets: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2

Security Groups:
  - ALB: $ALB_SG
  - EC2: $EC2_SG

EC2 Instances:
  - Instance 1: $INSTANCE_1 ($INSTANCE_1_IP)
  - Instance 2: $INSTANCE_2 ($INSTANCE_2_IP)
  - SSH Key: ~/.ssh/${KEY_NAME}.pem

Load Balancer:
  - ALB ARN: $ALB_ARN
  - ALB DNS: $ALB_DNS
  - Target Group: $TARGET_GROUP_ARN

SSH Commands:
  ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@$INSTANCE_1_IP
  ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@$INSTANCE_2_IP

Application URL:
  http://$ALB_DNS

GitHub Secrets to Configure:
  AWS_ACCESS_KEY_ID: (already set)
  AWS_SECRET_ACCESS_KEY: (already set)
  AWS_REGION: $REGION
  EC2_SSH_PRIVATE_KEY: (see ~/.ssh/${KEY_NAME}.pem)
  EC2_SERVER_1_IP: $INSTANCE_1_IP
  EC2_SERVER_2_IP: $INSTANCE_2_IP
  EC2_USER: ubuntu
  ALB_ENDPOINT: $ALB_DNS

========================================
EOF

log_success "Infrastructure details saved to ~/infrastructure-details.txt"

echo ""
log_info "======================================"
log_success "Infrastructure Setup Complete!"
log_info "======================================"
echo ""
echo "Next steps:"
echo "1. Wait 2-3 minutes for instances to fully initialize"
echo "2. SSH to instances and run bootstrap script"
echo "3. Configure GitHub Secrets"
echo "4. Push code to trigger deployment"
echo ""
echo "View details: cat ~/infrastructure-details.txt"
echo "ALB URL: http://$ALB_DNS"
