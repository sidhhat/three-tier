# Zero-Downtime Deployment Guide
## Django Notes App - Production Deployment

This guide provides comprehensive instructions for deploying the Django Notes App with zero-downtime using Docker, GitHub Actions, AWS EC2, and Application Load Balancer.

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Initial Setup](#initial-setup)
4. [AWS Infrastructure Setup](#aws-infrastructure-setup)
5. [EC2 Configuration](#ec2-configuration)
6. [GitHub Actions Setup](#github-actions-setup)
7. [First Deployment](#first-deployment)
8. [Zero-Downtime Deployment Process](#zero-downtime-deployment-process)
9. [Monitoring & Maintenance](#monitoring--maintenance)
10. [Troubleshooting](#troubleshooting)
11. [Rollback Procedures](#rollback-procedures)

---

## Prerequisites

### Required Accounts & Access
- ✅ AWS Account with appropriate permissions
- ✅ Docker Hub account
- ✅ GitHub repository with Actions enabled
- ✅ Domain name (optional, for SSL)

### Local Development Tools
- Docker Desktop or Docker Engine
- AWS CLI v2
- Git
- SSH key pair for EC2 access

---

## Architecture Overview

```
┌─────────────┐
│   GitHub    │
│ Repository  │
└──────┬──────┘
       │ Push to main
       ▼
┌─────────────┐
│   GitHub    │
│   Actions   │◄───────── CI/CD Pipeline
└──────┬──────┘
       │ Build & Push
       ▼
┌─────────────┐
│ Docker Hub  │
│   Golden    │
│   Image     │
└──────┬──────┘
       │ Pull Image
       ▼
┌─────────────────────────────────────────┐
│          Rolling Deployment             │
│  ┌───────────┐       ┌───────────┐     │
│  │  EC2-1    │       │  EC2-2    │     │
│  │  Server   │       │  Server   │     │
│  └─────┬─────┘       └─────┬─────┘     │
└────────┼───────────────────┼───────────┘
         │                   │
         └─────────┬─────────┘
                   ▼
         ┌─────────────────┐
         │  Application    │
         │  Load Balancer  │
         │     (ALB)       │
         └────────┬────────┘
                  │
                  ▼
         ┌─────────────────┐
         │     Users       │
         └─────────────────┘
```

---

## Initial Setup

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/django-notes-app.git
cd django-notes-app
```

### 2. Configure Environment Variables

```bash
cp .env.example .env
nano .env
```

Update the following critical values:
- `SECRET_KEY`: Generate using `python -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())'`
- `DB_HOST`: Your RDS endpoint
- `DB_PASSWORD`: Secure database password
- `ALLOWED_HOSTS`: Your domain and ALB endpoint

### 3. Test Locally

```bash
# Build the production image
docker build -f Dockerfile.production -t django-notes-app:local .

# Run locally
docker run -d -p 8000:8000 --env-file .env django-notes-app:local

# Verify
curl http://localhost:8000/admin/login/
```

---

## AWS Infrastructure Setup

### Step 1: Create VPC & Subnets (Skip if using default VPC)

```bash
# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=notes-app-vpc}]'

# Create public subnets in 2 AZs
aws ec2 create-subnet --vpc-id vpc-xxxxx --cidr-block 10.0.1.0/24 --availability-zone us-east-1a
aws ec2 create-subnet --vpc-id vpc-xxxxx --cidr-block 10.0.2.0/24 --availability-zone us-east-1b
```

### Step 2: Create Security Groups

**ALB Security Group:**
```bash
aws ec2 create-security-group \
  --group-name notes-app-alb-sg \
  --description "Security group for ALB" \
  --vpc-id vpc-xxxxx

# Allow HTTP (80) and HTTPS (443)
aws ec2 authorize-security-group-ingress --group-id sg-xxxxx --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id sg-xxxxx --protocol tcp --port 443 --cidr 0.0.0.0/0
```

**EC2 Security Group:**
```bash
aws ec2 create-security-group \
  --group-name notes-app-ec2-sg \
  --description "Security group for EC2 instances" \
  --vpc-id vpc-xxxxx

# Allow SSH from your IP
aws ec2 authorize-security-group-ingress --group-id sg-yyyyy --protocol tcp --port 22 --cidr YOUR_IP/32

# Allow traffic from ALB on port 8000
aws ec2 authorize-security-group-ingress --group-id sg-yyyyy --protocol tcp --port 8000 --source-group sg-xxxxx
```

**RDS Security Group:**
```bash
aws ec2 create-security-group \
  --group-name notes-app-rds-sg \
  --description "Security group for RDS" \
  --vpc-id vpc-xxxxx

# Allow MySQL from EC2 security group
aws ec2 authorize-security-group-ingress --group-id sg-zzzzz --protocol tcp --port 3306 --source-group sg-yyyyy
```

### Step 3: Create RDS Instance

```bash
aws rds create-db-instance \
  --db-instance-identifier notes-app-db \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --master-username admin \
  --master-user-password YOUR_SECURE_PASSWORD \
  --allocated-storage 20 \
  --vpc-security-group-ids sg-zzzzz \
  --db-subnet-group-name your-db-subnet-group \
  --backup-retention-period 7 \
  --no-publicly-accessible
```

Wait for RDS to be available (5-10 minutes):
```bash
aws rds wait db-instance-available --db-instance-identifier notes-app-db
```

Get the endpoint:
```bash
aws rds describe-db-instances --db-instance-identifier notes-app-db --query 'DBInstances[0].Endpoint.Address' --output text
```

### Step 4: Launch EC2 Instances

```bash
# Launch Server 1
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.medium \
  --key-name your-key-pair \
  --security-group-ids sg-yyyyy \
  --subnet-id subnet-xxxxx \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=notes-app-server-1},{Key=Environment,Value=production}]' \
  --user-data file://scripts/bootstrap-ec2.sh

# Launch Server 2
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.medium \
  --key-name your-key-pair \
  --security-group-ids sg-yyyyy \
  --subnet-id subnet-yyyyy \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=notes-app-server-2},{Key=Environment,Value=production}]' \
  --user-data file://scripts/bootstrap-ec2.sh
```

### Step 5: Create Application Load Balancer

```bash
# Create ALB
aws elbv2 create-load-balancer \
  --name notes-app-alb \
  --subnets subnet-xxxxx subnet-yyyyy \
  --security-groups sg-xxxxx \
  --scheme internet-facing \
  --type application

# Create Target Group
aws elbv2 create-target-group \
  --name notes-app-targets \
  --protocol HTTP \
  --port 8000 \
  --vpc-id vpc-xxxxx \
  --health-check-protocol HTTP \
  --health-check-path /admin/login/ \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --deregistration-delay 30

# Register targets
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --targets Id=i-instance1 Id=i-instance2

# Create listener
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:... \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:...
```

---

## EC2 Configuration

### Connect to EC2 Instances

```bash
# Get instance IPs
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=notes-app-server-*" \
  --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# SSH to each server
ssh -i your-key.pem ubuntu@SERVER_IP
```

### Run Bootstrap Script (if not done via user-data)

```bash
sudo bash scripts/bootstrap-ec2.sh
```

### Configure Environment on Each Server

```bash
cd /opt/django-notes-app
sudo nano .env
```

Paste your production environment variables.

### Test Manual Deployment

```bash
# Set environment variables
export DOCKER_IMAGE=yourusername/django-notes-app
export IMAGE_TAG=latest

# Run deployment script
sudo bash scripts/deploy.sh
```

---

## GitHub Actions Setup

### Configure Repository Secrets

Go to: `Settings > Secrets and variables > Actions > New repository secret`

Add the following secrets:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `DOCKER_USERNAME` | Docker Hub username | `yourusername` |
| `DOCKER_PASSWORD` | Docker Hub token/password | `dckr_pat_xxxxx` |
| `AWS_ACCESS_KEY_ID` | AWS access key | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | `wJalrXUtnFEMI/K7MDENG/...` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `EC2_SSH_PRIVATE_KEY` | SSH private key content | `-----BEGIN RSA...` |
| `EC2_SERVER_1_IP` | Server 1 public IP | `54.123.45.67` |
| `EC2_SERVER_2_IP` | Server 2 public IP | `54.123.45.68` |
| `EC2_USER` | EC2 SSH username | `ubuntu` |
| `ALB_ENDPOINT` | ALB DNS name (optional) | `notes-app-alb-xxx.elb.amazonaws.com` |
| `SLACK_WEBHOOK_URL` | Slack webhook (optional) | `https://hooks.slack.com/...` |

### Verify Workflow File

The workflow file is located at: `.github/workflows/deploy.yml`

Review and customize if needed.

---

## First Deployment

### Trigger Deployment

```bash
# Make a change to trigger deployment
git add .
git commit -m "Initial production deployment"
git push origin main
```

### Monitor Deployment

1. Go to GitHub Actions tab in your repository
2. Watch the workflow execution
3. Check each job's logs
4. Verify all steps complete successfully

### Verify Deployment

```bash
# Check ALB endpoint
curl http://your-alb-endpoint.elb.amazonaws.com/admin/login/

# Check individual servers
curl http://SERVER_1_IP:8000/admin/login/
curl http://SERVER_2_IP:8000/admin/login/

# Check target health in ALB
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:...
```

---

## Zero-Downtime Deployment Process

### How It Works

1. **Trigger**: Push to main branch
2. **Build**: GitHub Actions builds new Docker image
3. **Push**: Golden image pushed to Docker Hub with tags (latest, git-sha, build-number)
4. **Deploy Server 1**:
   - Marks instance as draining in ALB
   - Waits for existing connections to complete (30s)
   - Pulls new image
   - Stops old container gracefully
   - Starts new container
   - Waits for health check to pass
   - Registers instance back to ALB
5. **Deploy Server 2**: Repeats process for second server
6. **Verification**: Confirms both servers healthy

### Deployment Timeline

```
Time    Server 1          Server 2          ALB Status
-----   ---------------   ---------------   -----------
0:00    Draining          Serving           100% capacity
0:30    Deploying         Serving           50% capacity
1:00    Health check      Serving           50% capacity
1:30    Serving           Serving           100% capacity
2:00    Serving           Draining          100% capacity
2:30    Serving           Deploying         50% capacity
3:00    Serving           Health check      50% capacity
3:30    Serving           Serving           100% capacity
```

**Total downtime: 0 seconds** ✅

---

## Monitoring & Maintenance

### Health Checks

```bash
# Run comprehensive health check
ssh ubuntu@SERVER_IP 'cd /opt/django-notes-app && bash scripts/health-check.sh'
```

### View Logs

```bash
# Application logs
docker logs -f django-notes-app

# System logs
journalctl -u django-notes-app.service -f
```

### CloudWatch Monitoring (if configured)

- EC2 CPU, Memory, Disk metrics
- ALB request count, latency, error rates
- Target health status
- Custom application metrics

### Backup Database

```bash
# Manual RDS snapshot
aws rds create-db-snapshot \
  --db-instance-identifier notes-app-db \
  --db-snapshot-identifier notes-app-backup-$(date +%Y%m%d-%H%M%S)
```

---

## Troubleshooting

### Deployment Failed on Server 1

```bash
# Check GitHub Actions logs first
# Then SSH to server and check:

# Container status
docker ps -a

# Container logs
docker logs django-notes-app

# Manual health check
curl -v http://localhost:8000/admin/login/

# System resources
htop
df -h

# Re-run deployment manually
cd /opt/django-notes-app
export DOCKER_IMAGE=yourusername/django-notes-app
export IMAGE_TAG=latest
sudo bash scripts/deploy.sh
```

### Health Check Failing

```bash
# Check application is running
docker ps

# Check port is listening
netstat -tuln | grep 8000

# Check application logs
docker logs django-notes-app | tail -100

# Check database connectivity
docker exec django-notes-app python manage.py dbshell
```

### ALB Showing Unhealthy Targets

```bash
# Check target health
aws elbv2 describe-target-health --target-group-arn arn:aws:...

# Check security groups allow ALB -> EC2:8000
# Check application is responding on port 8000
curl http://localhost:8000/admin/login/
```

---

## Rollback Procedures

### Automatic Rollback

The deployment script includes automatic rollback if health checks fail.

### Manual Rollback

```bash
# SSH to affected server
ssh ubuntu@SERVER_IP

# List recent Docker images
docker images

# Deploy previous version
export DOCKER_IMAGE=yourusername/django-notes-app
export IMAGE_TAG=previous-working-sha
sudo bash /opt/django-notes-app/scripts/deploy.sh
```

### Emergency Rollback via GitHub

```bash
# Revert commit
git revert HEAD
git push origin main

# Or rollback to specific commit
git reset --hard GOOD_COMMIT_SHA
git push origin main --force
```

---

## Best Practices

1. **Always test in staging first**
2. **Monitor deployments actively**
3. **Keep at least 3 Docker image versions**
4. **Regular database backups**
5. **Update security patches monthly**
6. **Review logs weekly**
7. **Test rollback procedures quarterly**
8. **Document all configuration changes**

---

## Support & Resources

- **GitHub Issues**: Report bugs and feature requests
- **Documentation**: Keep this file updated
- **Team Chat**: Slack channel for deployment notifications
- **On-call**: Escalation procedures for production issues

---

## Change Log

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2025-12-18 | 1.0.0 | Initial deployment guide | DevOps Team |

---

**Last Updated**: December 18, 2025
