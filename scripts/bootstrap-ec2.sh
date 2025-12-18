#!/bin/bash

################################################################################
# EC2 Bootstrap Script for Django Notes App
# Run this script on each new EC2 instance to set up the environment
################################################################################

set -e
set -u

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_info "=========================================="
log_info "EC2 Instance Bootstrap for Django Notes App"
log_info "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    log_error "Please run as root or with sudo"
    exit 1
fi

# Step 1: Update system packages
log_info "Step 1: Updating system packages..."
apt-get update -y
apt-get upgrade -y
log_success "System packages updated"

# Step 2: Install required packages
log_info "Step 2: Installing required packages..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    git \
    vim \
    htop \
    jq \
    unzip
log_success "Required packages installed"

# Step 3: Install Docker
log_info "Step 3: Installing Docker..."
if ! command -v docker &> /dev/null; then
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Set up Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    log_success "Docker installed successfully"
else
    log_info "Docker already installed"
fi

# Verify Docker installation
docker --version

# Step 4: Install Docker Compose (standalone)
log_info "Step 4: Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_VERSION="2.24.0"
    curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    log_success "Docker Compose installed successfully"
else
    log_info "Docker Compose already installed"
fi

docker-compose --version

# Step 5: Install AWS CLI
log_info "Step 5: Installing AWS CLI..."
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
    log_success "AWS CLI installed successfully"
else
    log_info "AWS CLI already installed"
fi

aws --version

# Step 6: Create application directory
log_info "Step 6: Setting up application directory..."
APP_DIR="/opt/django-notes-app"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

# Create deployment script directory
mkdir -p "$APP_DIR/scripts"

log_success "Application directory created at $APP_DIR"

# Step 7: Configure Docker Hub credentials (if provided)
log_info "Step 7: Setting up Docker Hub credentials..."
echo ""
read -p "Enter Docker Hub username (or press Enter to skip): " DOCKER_USERNAME
if [ -n "$DOCKER_USERNAME" ]; then
    read -sp "Enter Docker Hub password/token: " DOCKER_PASSWORD
    echo ""
    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
    log_success "Docker Hub credentials configured"
else
    log_info "Skipping Docker Hub authentication"
fi

# Step 8: Create environment file template
log_info "Step 8: Creating environment file template..."
cat > "$APP_DIR/.env.template" << 'EOF'
# Django Settings
SECRET_KEY=your-secret-key-here
DEBUG=False
ALLOWED_HOSTS=*

# Database Settings
DB_ENGINE=django.db.backends.mysql
DB_NAME=notes_db
DB_USER=notes_user
DB_PASSWORD=your-db-password
DB_HOST=your-rds-endpoint.rds.amazonaws.com
DB_PORT=3306

# Docker Settings
DOCKER_IMAGE=yourusername/django-notes-app
IMAGE_TAG=latest
EOF

log_info "Please copy .env.template to .env and update with actual values"
log_info "Command: cp $APP_DIR/.env.template $APP_DIR/.env && nano $APP_DIR/.env"

# Step 9: Create systemd service for auto-restart
log_info "Step 9: Creating systemd service..."
cat > /etc/systemd/system/django-notes-app.service << EOF
[Unit]
Description=Django Notes Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/docker start django-notes-app
ExecStop=/usr/bin/docker stop -t 30 django-notes-app
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
log_success "Systemd service created"

# Step 10: Configure log rotation
log_info "Step 10: Setting up log rotation..."
cat > /etc/logrotate.d/django-notes-app << 'EOF'
/var/log/django-notes-app/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    create 0644 root root
    sharedscripts
    postrotate
        docker kill -s USR1 django-notes-app 2>/dev/null || true
    endscript
}
EOF

mkdir -p /var/log/django-notes-app
log_success "Log rotation configured"

# Step 11: Configure firewall (UFW)
log_info "Step 11: Configuring firewall..."
if command -v ufw &> /dev/null; then
    # Allow SSH
    ufw allow 22/tcp
    # Allow HTTP
    ufw allow 80/tcp
    # Allow HTTPS
    ufw allow 443/tcp
    # Allow application port
    ufw allow 8000/tcp
    
    # Enable UFW (be careful with this on remote servers)
    # Uncomment the next line only if you're sure
    # echo "y" | ufw enable
    
    log_success "Firewall rules configured (run 'ufw enable' to activate)"
else
    log_info "UFW not found, skipping firewall configuration"
fi

# Step 12: Install CloudWatch agent (optional)
log_info "Step 12: Installing CloudWatch agent (optional)..."
read -p "Install CloudWatch agent for monitoring? (y/n): " INSTALL_CW
if [ "$INSTALL_CW" = "y" ] || [ "$INSTALL_CW" = "Y" ]; then
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i -E ./amazon-cloudwatch-agent.deb
    rm amazon-cloudwatch-agent.deb
    log_success "CloudWatch agent installed"
else
    log_info "Skipping CloudWatch agent installation"
fi

# Step 13: Set up automatic security updates
log_info "Step 13: Configuring automatic security updates..."
apt-get install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
log_success "Automatic security updates configured"

# Step 14: Create health check script
log_info "Step 14: Creating health check script..."
cat > "$APP_DIR/scripts/health-check.sh" << 'EOF'
#!/bin/bash
# Health check script for Django Notes App

HEALTH_URL="${HEALTH_URL:-http://localhost:8000/admin/login/}"
MAX_ATTEMPTS=3
TIMEOUT=5

for i in $(seq 1 $MAX_ATTEMPTS); do
    if curl -f -s -o /dev/null -m $TIMEOUT "$HEALTH_URL"; then
        echo "Health check passed"
        exit 0
    fi
    sleep 2
done

echo "Health check failed after $MAX_ATTEMPTS attempts"
exit 1
EOF

chmod +x "$APP_DIR/scripts/health-check.sh"
log_success "Health check script created"

# Step 15: Display summary
log_info "=========================================="
log_success "Bootstrap completed successfully!"
log_info "=========================================="
log_info "Summary:"
log_info "  - Application directory: $APP_DIR"
log_info "  - Environment template: $APP_DIR/.env.template"
log_info "  - Systemd service: django-notes-app.service"
log_info "  - Docker version: $(docker --version)"
log_info "  - Docker Compose version: $(docker-compose --version)"
log_info "=========================================="
log_info "Next steps:"
log_info "  1. Configure environment: cp $APP_DIR/.env.template $APP_DIR/.env"
log_info "  2. Edit environment file: nano $APP_DIR/.env"
log_info "  3. Run deployment script from CI/CD pipeline"
log_info "=========================================="

# Optional: Display system information
log_info "System Information:"
echo "  - Hostname: $(hostname)"
echo "  - IP Address: $(hostname -I | awk '{print $1}')"
echo "  - OS: $(lsb_release -d | cut -f2)"
echo "  - Kernel: $(uname -r)"
echo "  - Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "  - Disk: $(df -h / | awk 'NR==2 {print $2}')"
log_info "=========================================="
