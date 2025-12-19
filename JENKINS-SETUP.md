# Jenkins CI/CD Setup Guide
## Django Notes App - Complete Jenkins Pipeline Configuration

This guide provides step-by-step instructions for setting up Jenkins for zero-downtime deployment of the Django Notes App.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Jenkins Installation](#jenkins-installation)
4. [Jenkins Configuration](#jenkins-configuration)
5. [Pipeline Setup](#pipeline-setup)
6. [Credentials Configuration](#credentials-configuration)
7. [Running the Pipeline](#running-the-pipeline)
8. [Troubleshooting](#troubleshooting)

---

## Overview

### Jenkins Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Jenkins Server                            │
│  ┌────────────────────────────────────────────────────────┐ │
│  │            Jenkins Pipeline (Jenkinsfile)              │ │
│  │                                                         │ │
│  │  1. Checkout Code from GitHub                          │ │
│  │  2. Build Docker Image (Dockerfile.production)         │ │
│  │  3. Test Image                                         │ │
│  │  4. Push to DockerHub                                  │ │
│  │  5. Deploy to EC2 Server 1 (Zero-downtime)            │ │
│  │  6. Verify Server 1                                    │ │
│  │  7. Deploy to EC2 Server 2 (Zero-downtime)            │ │
│  │  8. Verify Server 2                                    │ │
│  │  9. Final Verification (ALB)                           │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
              ┌─────────────────────────┐
              │      DockerHub          │
              │   (Golden Images)       │
              └───────────┬─────────────┘
                          │
          ┌───────────────┴────────────────┐
          ▼                                ▼
    ┌──────────┐                    ┌──────────┐
    │  EC2-1   │                    │  EC2-2   │
    │  Server  │                    │  Server  │
    └────┬─────┘                    └────┬─────┘
         │                                │
         └────────────┬───────────────────┘
                      ▼
               ┌─────────────┐
               │     ALB     │
               └─────────────┘
```

### Key Features

✅ **Zero-downtime deployment** - Rolling updates with health checks  
✅ **Automated testing** - Container validation before deployment  
✅ **Multi-tag images** - latest, build number, git commit  
✅ **Sequential deployment** - Server 1 → Verify → Server 2  
✅ **Automatic rollback** - Failed deployments revert automatically  
✅ **Health monitoring** - Comprehensive health checks at each stage  

---

## Prerequisites

### System Requirements

- **OS**: Ubuntu 20.04 or 22.04 LTS
- **RAM**: Minimum 2GB (4GB recommended)
- **CPU**: 2 cores minimum
- **Disk**: 20GB free space
- **Java**: OpenJDK 17 (installed automatically)

### Required Access

- ✅ GitHub repository access
- ✅ DockerHub account with push access
- ✅ SSH access to both EC2 servers
- ✅ EC2 SSH private key file
- ✅ Sudo privileges on Jenkins server

---

## Jenkins Installation

### Option 1: Quick Installation (Recommended)

```bash
cd /home/ubuntu/django-notes-app

# Make script executable
chmod +x scripts/install-jenkins.sh

# Run installation (requires sudo)
sudo bash scripts/install-jenkins.sh
```

### Option 2: Manual Installation

```bash
# Update system
sudo apt-get update

# Install Java 17
sudo apt-get install -y openjdk-17-jdk

# Add Jenkins repository
wget -q -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
  https://pkg.jenkins.io/debian-stable binary/ | \
  sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Install Jenkins
sudo apt-get update
sudo apt-get install -y jenkins

# Start Jenkins
sudo systemctl start jenkins
sudo systemctl enable jenkins

# Get initial admin password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

### Verify Installation

```bash
# Check Jenkins status
sudo systemctl status jenkins

# Check if Jenkins is listening
netstat -tuln | grep 8080

# Get Jenkins URL
echo "http://$(hostname -I | awk '{print $1}'):8080"
```

---

## Jenkins Configuration

### 1. Initial Setup Wizard

1. **Open Jenkins**: Navigate to `http://YOUR_SERVER_IP:8080`
2. **Enter Admin Password**: Use the password from installation
3. **Install Suggested Plugins**: Click "Install suggested plugins"
4. **Create Admin User**: Fill in your details
5. **Configure Jenkins URL**: Set to your server IP or domain

### 2. Install Required Plugins

Navigate to: **Manage Jenkins** → **Manage Plugins** → **Available**

Install these plugins:
- ✅ **Docker Pipeline** - Docker operations in pipeline
- ✅ **SSH Agent** - SSH key management
- ✅ **Credentials Binding** - Secure credential handling
- ✅ **Git** - Git repository integration
- ✅ **Pipeline** - Pipeline functionality (usually pre-installed)
- ✅ **Workspace Cleanup** - Clean workspace between builds

After installation, restart Jenkins:
```bash
sudo systemctl restart jenkins
```

### 3. Configure Jenkins for Docker

Add Jenkins user to docker group:
```bash
# Add jenkins user to docker group
sudo usermod -aG docker jenkins

# Restart Jenkins
sudo systemctl restart jenkins

# Verify
sudo -u jenkins docker ps
```

---

## Credentials Configuration

### 1. DockerHub Credentials

**Manage Jenkins** → **Manage Credentials** → **System** → **Global credentials** → **Add Credentials**

```
Kind: Username with password
Scope: Global
Username: YOUR_DOCKERHUB_USERNAME
Password: YOUR_DOCKERHUB_PASSWORD or TOKEN
ID: dockerhub-credentials
Description: DockerHub credentials for pushing images
```

### 2. EC2 SSH Key

**Method A: SSH Username with private key (Recommended)**

```
Kind: SSH Username with private key
Scope: Global
ID: ec2-ssh-key
Username: ubuntu
Private Key: Enter directly
   - Click "Add" → paste content of django-notes-key.pem
Description: EC2 SSH key for deployment
```

**Method B: Upload key file to Jenkins server**

```bash
# Copy SSH key to Jenkins workspace
sudo mkdir -p /var/lib/jenkins/.ssh
sudo cp /path/to/django-notes-key.pem /var/lib/jenkins/.ssh/
sudo chown -R jenkins:jenkins /var/lib/jenkins/.ssh
sudo chmod 600 /var/lib/jenkins/.ssh/django-notes-key.pem
```

### 3. GitHub Credentials (Optional - for private repos)

```
Kind: Username with password
Username: YOUR_GITHUB_USERNAME
Password: YOUR_GITHUB_PERSONAL_ACCESS_TOKEN
ID: github-credentials
Description: GitHub access token
```

---

## Pipeline Setup

### 1. Create New Pipeline Job

1. **Dashboard** → **New Item**
2. **Name**: `django-notes-app-pipeline`
3. **Type**: Select "Pipeline"
4. Click **OK**

### 2. Configure Pipeline

#### General Settings
- ✅ **Description**: "Zero-downtime deployment pipeline for Django Notes App"
- ✅ **Discard old builds**: Keep last 10 builds

#### Build Triggers (Choose one)

**Option A: Poll SCM (Check GitHub periodically)**
```
Schedule: H/5 * * * *  (Every 5 minutes)
```

**Option B: GitHub Webhook (Recommended for instant builds)**
1. In Jenkins: Enable "GitHub hook trigger for GITScm polling"
2. In GitHub: Settings → Webhooks → Add webhook
   - Payload URL: `http://YOUR_JENKINS_URL:8080/github-webhook/`
   - Content type: `application/json`
   - Events: Just the push event

**Option C: Manual Build Only**
- Leave Build Triggers empty

#### Pipeline Configuration

```
Definition: Pipeline script from SCM
SCM: Git
Repository URL: https://github.com/sidhhat/three-tier.git
Credentials: (none for public repo, or select github-credentials)
Branch: */main
Script Path: Jenkinsfile
```

### 3. Save Pipeline

Click **Save** to create the pipeline

---

## Running the Pipeline

### First Build

1. **Open pipeline** → Click "Build Now"
2. **Monitor build**: Click on build number → "Console Output"
3. **Watch stages**: View stage progress in "Stage View"

### Build Stages Overview

| Stage | Duration | Description |
|-------|----------|-------------|
| Checkout | ~10s | Clone repository from GitHub |
| Build Docker Image | ~3-5min | Build production Docker image |
| Test Image | ~30s | Verify image works correctly |
| Push to DockerHub | ~2min | Upload images to DockerHub |
| Deploy to Server 1 | ~2min | Zero-downtime deployment to EC2-1 |
| Verify Server 1 | ~5s | Health check Server 1 |
| Deploy to Server 2 | ~2min | Zero-downtime deployment to EC2-2 |
| Verify Server 2 | ~5s | Health check Server 2 |
| Final Verification | ~10s | Test ALB and summarize |

**Total Time**: ~10-15 minutes per deployment

### Expected Output

```
╔════════════════════════════════════════════════════════════════════╗
║              DEPLOYMENT SUCCESSFUL                                 ║
╚════════════════════════════════════════════════════════════════════╝

🎉 Build: 42
📦 Image: vishal762/django-notes-app:latest
🔗 Commit: abc1234

🌐 Endpoints:
   ALB: http://django-notes-alb-1211580729.us-east-1.elb.amazonaws.com
   Server 1: http://44.201.15.190:8000
   Server 2: http://3.89.89.66:8000

╚════════════════════════════════════════════════════════════════════╝
```

---

## Customizing the Pipeline

### Update Environment Variables

Edit `Jenkinsfile` and modify the environment section:

```groovy
environment {
    // Docker Configuration
    DOCKER_IMAGE = 'YOUR_DOCKERHUB_USERNAME/YOUR_IMAGE_NAME'
    DOCKER_CREDENTIALS_ID = 'dockerhub-credentials'
    
    // EC2 Configuration
    EC2_SERVER_1 = 'YOUR_SERVER_1_IP'
    EC2_SERVER_2 = 'YOUR_SERVER_2_IP'
    EC2_USER = 'ubuntu'
    EC2_SSH_KEY_ID = 'ec2-ssh-key'
    
    // Application Configuration
    APP_PORT = '8000'
    CONTAINER_NAME = 'django-notes-app'
}
```

---

## Troubleshooting

### Issue 1: Permission Denied (Docker)

**Error**: `permission denied while trying to connect to the Docker daemon socket`

**Solution**:
```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### Issue 2: SSH Connection Failed

**Error**: `Host key verification failed`

**Solution**:
```bash
# Add to known_hosts
sudo -u jenkins ssh -o StrictHostKeyChecking=no ubuntu@EC2_IP exit
```

### Issue 3: DockerHub Push Failed

**Error**: `denied: requested access to the resource is denied`

**Solutions**:
1. Verify credentials are correct
2. Check DockerHub username matches image name
3. Ensure you're logged in:
   ```bash
   docker login
   ```

### Issue 4: Health Check Timeout

**Error**: `Container health check timeout`

**Solutions**:
1. Increase `HEALTH_CHECK_TIMEOUT` in Jenkinsfile
2. Check application logs:
   ```bash
   ssh ubuntu@EC2_IP "docker logs django-notes-app"
   ```
3. Verify health check endpoint is working

### Issue 5: Port Already in Use

**Error**: `port 8000 is already allocated`

**Solution**:
```bash
ssh ubuntu@EC2_IP "docker stop django-notes-app && docker rm django-notes-app"
```

### Viewing Logs

**Jenkins Logs**:
```bash
sudo tail -f /var/lib/jenkins/logs/jenkins.log
```

**Application Logs**:
```bash
ssh ubuntu@EC2_IP "docker logs -f django-notes-app"
```

**Build Logs**:
- In Jenkins → Build → Console Output

---

## Security Best Practices

### 1. Secure Jenkins

```bash
# Enable security
# Manage Jenkins → Configure Global Security
- Enable "Jenkins' own user database"
- Disable "Allow users to sign up"
- Enable "Project-based Matrix Authorization Strategy"
```

### 2. Use Jenkins Behind Nginx (Optional)

```nginx
server {
    listen 80;
    server_name jenkins.yourdomain.com;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 3. Backup Jenkins

```bash
# Backup Jenkins home directory
sudo tar -czf jenkins-backup-$(date +%Y%m%d).tar.gz /var/lib/jenkins

# Backup to S3
aws s3 cp jenkins-backup-$(date +%Y%m%d).tar.gz s3://your-backup-bucket/
```

---

## Monitoring & Maintenance

### Monitor Builds

- **Blue Ocean**: Install plugin for better visualization
- **Build History**: View past builds and trends
- **Stage View**: See which stage failed/succeeded

### Regular Maintenance

```bash
# Clean old Docker images
docker system prune -a -f

# Clean Jenkins workspace
# In Jenkins: Manage Jenkins → Prepare for Shutdown → Clean up workspace

# Update Jenkins
sudo apt-get update
sudo apt-get upgrade jenkins
```

---

## Next Steps

✅ Jenkins installed and configured  
✅ Pipeline created and tested  
✅ Zero-downtime deployment working  

### Additional Enhancements

1. **Slack Notifications**: Add Slack plugin for build notifications
2. **Email Alerts**: Configure email on build failure
3. **Blue Ocean**: Install for better UI
4. **Parallel Stages**: Deploy to both servers simultaneously (advanced)
5. **Automated Tests**: Add more comprehensive testing stage

---

## Support & Resources

- **Jenkins Documentation**: https://www.jenkins.io/doc/
- **Pipeline Syntax**: https://www.jenkins.io/doc/book/pipeline/syntax/
- **Plugins**: https://plugins.jenkins.io/

---

**🎉 Your Jenkins CI/CD pipeline is ready!**

Push code to GitHub and watch Jenkins automatically build and deploy with zero downtime!
