# Terraform AWS Infrastructure

This directory contains Terraform configuration to deploy the complete AWS infrastructure for the Django Notes App with zero-downtime deployment.

## 🏗️ Infrastructure Components

- **VPC**: Custom VPC with public subnets in 2 availability zones
- **EC2 Instances**: 2x t2.micro instances (free tier eligible)
- **Application Load Balancer**: HTTP load balancer with health checks
- **Security Groups**: Layered security for ALB and EC2
- **SSH Key Pair**: Auto-generated or use your own

## 📋 Prerequisites

- AWS CLI configured with credentials
- Terraform installed (>= 1.0)
- AWS account with appropriate permissions

## 🚀 Quick Start

### 1. Install Terraform

```bash
# Download and install Terraform
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform version
```

### 2. Configure Variables

Edit `terraform.tfvars` to customize:

```hcl
aws_region      = "us-east-1"
project_name    = "django-notes"
instance_type   = "t2.micro"
docker_username = "your-docker-username"
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy infrastructure
terraform apply

# Auto-approve (skip confirmation)
terraform apply -auto-approve
```

### 4. Get Outputs

```bash
# View all outputs
terraform output

# Get specific output
terraform output alb_url
terraform output ec2_server_1_public_ip

# Get GitHub secrets configuration
terraform output github_secrets
```

## 📊 Terraform Commands

```bash
# Initialize workspace
terraform init

# Format code
terraform fmt

# Validate configuration
terraform validate

# Plan changes
terraform plan

# Apply changes
terraform apply

# Destroy infrastructure
terraform destroy

# Show current state
terraform show

# List resources
terraform state list
```

## 🔧 Configuration Files

| File | Purpose |
|------|---------|
| `main.tf` | Main infrastructure resources |
| `variables.tf` | Input variable definitions |
| `outputs.tf` | Output value definitions |
| `terraform.tfvars` | Variable values |
| `.gitignore` | Files to ignore in git |

## 📤 Outputs

After deployment, you'll get:

- **ALB URL**: Application access point
- **EC2 IPs**: Public IPs for both servers
- **SSH Commands**: Ready-to-use SSH commands
- **GitHub Secrets**: Values to configure in GitHub

## 💰 Cost Estimation

Using t2.micro (free tier eligible):
- EC2: Free tier or ~$8/month each
- ALB: ~$20/month
- Data transfer: ~$9/month per 100GB
- **Total**: ~$45-50/month (or free with AWS Free Tier)

## 🔒 Security

- Security groups with minimal required access
- SSH key pair for EC2 access
- HTTPS support (certificate not included)
- VPC network isolation

## 🗑️ Cleanup

To destroy all infrastructure:

```bash
terraform destroy
```

**Warning**: This will delete all resources. Make sure to backup any data!

## 📝 Customization

### Change Instance Type

Edit `terraform.tfvars`:
```hcl
instance_type = "t3.medium"  # For production
```

### Use Your Own SSH Key

Edit `terraform.tfvars`:
```hcl
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EA..."
```

### Different Region

Edit `terraform.tfvars`:
```hcl
aws_region = "us-west-2"
```

## 🐛 Troubleshooting

### Error: No AWS credentials

```bash
# Configure AWS CLI
aws configure
```

### Error: SSH key already exists

```bash
# Use existing key or delete from AWS
terraform destroy -target=aws_key_pair.main
terraform apply
```

### Error: Resource limit exceeded

Check your AWS account limits in AWS Console.

## 📚 Next Steps

1. Wait 2-3 minutes for EC2 instances to initialize
2. SSH to servers and run bootstrap script
3. Configure GitHub Secrets with Terraform outputs
4. Push code to trigger deployment

## 🔗 Related Documentation

- [Main README](../README-PRODUCTION.md)
- [Deployment Guide](../DEPLOYMENT.md)
- [Quick Start](../QUICKSTART.md)
- [AWS Infrastructure](../AWS-INFRASTRUCTURE.md)
