#!/bin/bash

################################################################################
# Jenkins Installation Script for Ubuntu
# This script installs Jenkins with all required dependencies
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    log_error "Please run as root or with sudo"
    exit 1
fi

log_info "Starting Jenkins installation..."

# Update system
log_info "Updating system packages..."
apt-get update

# Install Java (Jenkins requires Java 11 or 17)
log_info "Installing Java 17..."
apt-get install -y openjdk-17-jdk

# Verify Java installation
java -version
log_success "Java installed successfully"

# Add Jenkins repository
log_info "Adding Jenkins repository..."
wget -q -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
  https://pkg.jenkins.io/debian-stable binary/ | \
  tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Update package list
apt-get update

# Install Jenkins
log_info "Installing Jenkins..."
apt-get install -y jenkins

# Start Jenkins service
log_info "Starting Jenkins service..."
systemctl start jenkins
systemctl enable jenkins

# Wait for Jenkins to start
log_info "Waiting for Jenkins to start (this may take a minute)..."
sleep 30

# Get initial admin password
log_success "Jenkins installation completed!"
echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                   JENKINS SETUP INFORMATION                        ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo "🌐 Jenkins URL: http://$(hostname -I | awk '{print $1}'):8080"
echo ""
echo "🔑 Initial Admin Password:"
if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    cat /var/lib/jenkins/secrets/initialAdminPassword
else
    echo "Password file not ready yet. Run this command in a few minutes:"
    echo "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
fi
echo ""
echo "📋 Next Steps:"
echo "   1. Open Jenkins URL in your browser"
echo "   2. Enter the initial admin password"
echo "   3. Install suggested plugins"
echo "   4. Create admin user"
echo "   5. Install additional plugins:"
echo "      - Docker Pipeline"
echo "      - SSH Agent"
echo "      - Credentials Binding"
echo "      - Git"
echo "   6. Configure Jenkins credentials (DockerHub, SSH keys)"
echo ""
echo "╚════════════════════════════════════════════════════════════════════╝"
