# 🚀 Jenkins CI/CD - Quick Start

## What's Been Set Up

Your project is now configured for **Jenkins-based CI/CD** pipeline with zero-downtime deployment!

---

## 📦 What You Have

### 1. **Complete Jenkinsfile** ✅
- Zero-downtime rolling deployment
- Automated Docker build & push
- Health checks at every stage
- Sequential deployment to 2 servers
- Automatic rollback on failure

### 2. **Jenkins Installation Script** ✅
- One-command Jenkins installation
- Auto-configures all dependencies
- Located: `scripts/install-jenkins.sh`

### 3. **Complete Documentation** ✅
- Full setup guide: `JENKINS-SETUP.md`
- Troubleshooting included
- Credentials configuration
- Security best practices

### 4. **GitHub Actions Archived** ✅
- Moved to `.github/workflows-archive/`
- Can be restored if needed

---

## 🎯 Next Steps (In Order)

### Step 1: Install Jenkins

```bash
cd /home/ubuntu/django-notes-app
sudo bash scripts/install-jenkins.sh
```

**Time**: ~5 minutes  
**What it does**: Installs Java 17 + Jenkins, starts service

### Step 2: Access Jenkins

```bash
# Get your Jenkins URL
echo "http://$(hostname -I | awk '{print $1}'):8080"

# Get initial admin password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Open the URL in your browser and use the password.

### Step 3: Complete Jenkins Setup

1. **Install suggested plugins** (wait ~5 minutes)
2. **Create admin user** (fill in your details)
3. **Install additional plugins**:
   - Docker Pipeline
   - SSH Agent
   - Credentials Binding

### Step 4: Configure Jenkins for Docker

```bash
# Add Jenkins user to docker group
sudo usermod -aG docker jenkins

# Restart Jenkins
sudo systemctl restart jenkins
```

### Step 5: Add Credentials

In Jenkins: **Manage Jenkins** → **Credentials** → **Add Credentials**

**A. DockerHub Credentials**
```
Type: Username with password
ID: dockerhub-credentials
Username: vishal762
Password: YOUR_DOCKERHUB_PASSWORD
```

**B. EC2 SSH Key**
```
Type: SSH Username with private key
ID: ec2-ssh-key
Username: ubuntu
Private Key: [Paste content of terraform/django-notes-key.pem]
```

### Step 6: Create Pipeline

1. **Dashboard** → **New Item**
2. **Name**: `django-notes-app-pipeline`
3. **Type**: Pipeline
4. **Configuration**:
   ```
   Definition: Pipeline script from SCM
   SCM: Git
   Repository: https://github.com/sidhhat/three-tier.git
   Branch: */main
   Script Path: Jenkinsfile
   ```
5. **Save**

### Step 7: Run First Build

1. Click **"Build Now"**
2. Watch the magic happen! ✨

---

## 📊 Pipeline Overview

```
┌─────────────────────────────────────────────────────────┐
│  1. Checkout         │  Clone from GitHub               │
│  2. Build Image      │  Docker build (3-5 min)          │
│  3. Test Image       │  Verify it works                 │
│  4. Push DockerHub   │  Upload golden image             │
│  5. Deploy Server 1  │  Zero-downtime update            │
│  6. Verify Server 1  │  Health check                    │
│  7. Deploy Server 2  │  Zero-downtime update            │
│  8. Verify Server 2  │  Health check                    │
│  9. Final Check      │  Test ALB endpoint               │
└─────────────────────────────────────────────────────────┘

Total Time: ~10-15 minutes
```

---

## 🎉 What Happens When You Push Code

1. **Push to GitHub** → `git push origin main`
2. **Jenkins detects change** (if webhook/polling enabled)
3. **Pipeline runs automatically**:
   - Builds new Docker image
   - Tests it
   - Pushes to DockerHub
   - Deploys to Server 1 with zero downtime
   - Verifies Server 1
   - Deploys to Server 2 with zero downtime
   - Verifies Server 2
   - Tests ALB
4. **Done!** New version live with ZERO downtime

---

## 📝 Important Files

| File | Purpose |
|------|---------|
| `Jenkinsfile` | Pipeline definition |
| `JENKINS-SETUP.md` | Complete setup guide |
| `scripts/install-jenkins.sh` | Jenkins installation |
| `Dockerfile.production` | Production Docker image |
| `terraform/django-notes-key.pem` | EC2 SSH key |

---

## 🔧 Configuration Variables

Update these in `Jenkinsfile` if needed:

```groovy
DOCKER_IMAGE = 'vishal762/django-notes-app'
EC2_SERVER_1 = '44.201.15.190'
EC2_SERVER_2 = '3.89.89.66'
APP_PORT = '8000'
```

---

## 🆘 Quick Troubleshooting

### Jenkins won't start
```bash
sudo systemctl status jenkins
sudo journalctl -u jenkins -n 50
```

### Docker permission denied
```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### Can't SSH to EC2
```bash
# Test SSH manually
ssh -i terraform/django-notes-key.pem ubuntu@44.201.15.190
```

### Build failing
- Check Jenkins console output
- Verify credentials are configured
- Ensure EC2 servers are running

---

## 📚 Full Documentation

For detailed information, see **JENKINS-SETUP.md**

---

## 🎯 Current Status

✅ Jenkinsfile created with zero-downtime deployment  
✅ Installation script ready  
✅ Complete documentation provided  
✅ GitHub Actions archived (can be restored)  
⏳ **Waiting for Jenkins installation and setup**

---

## 💡 Pro Tips

1. **Enable GitHub Webhooks** for instant builds on push
2. **Use Blue Ocean plugin** for better visualization
3. **Set up Slack notifications** for build alerts
4. **Regular backups** of `/var/lib/jenkins`

---

**Ready to install Jenkins?**

```bash
sudo bash scripts/install-jenkins.sh
```

Then follow Step 2 onwards! 🚀
