#!/bin/bash

################################################################################
# Zero-Downtime Deployment Script for Django Notes App
# This script performs a rolling update of the Docker container
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOCKER_IMAGE="${DOCKER_IMAGE:-yourusername/django-notes-app}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
CONTAINER_NAME="${CONTAINER_NAME:-django-notes-app}"
CONTAINER_PORT="${CONTAINER_PORT:-8000}"
HOST_PORT="${HOST_PORT:-8000}"
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-http://localhost:8000/admin/login/}"
MAX_HEALTH_CHECK_ATTEMPTS=30
HEALTH_CHECK_INTERVAL=2

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if container is running
is_container_running() {
    docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

# Function to check if container exists (running or stopped)
container_exists() {
    docker ps -a --filter "name=${CONTAINER_NAME}" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

# Function to wait for health check
wait_for_health_check() {
    local attempts=0
    log_info "Waiting for application health check..."
    
    while [ $attempts -lt $MAX_HEALTH_CHECK_ATTEMPTS ]; do
        if curl -f -s -o /dev/null "$HEALTH_CHECK_URL"; then
            log_success "Health check passed!"
            return 0
        fi
        
        attempts=$((attempts + 1))
        echo -n "."
        sleep $HEALTH_CHECK_INTERVAL
    done
    
    log_error "Health check failed after $MAX_HEALTH_CHECK_ATTEMPTS attempts"
    return 1
}

# Function to get current container ID
get_current_container_id() {
    docker ps --filter "name=${CONTAINER_NAME}" --format "{{.ID}}" | head -n 1
}

# Function to perform rollback
rollback() {
    log_warning "Performing rollback..."
    
    if [ -n "${OLD_CONTAINER_ID:-}" ]; then
        log_info "Starting old container: ${OLD_CONTAINER_ID}"
        docker start "$OLD_CONTAINER_ID" || true
        
        if wait_for_health_check; then
            log_success "Rollback successful!"
        else
            log_error "Rollback failed - manual intervention required!"
        fi
    else
        log_error "No old container to rollback to!"
    fi
}

# Main deployment process
main() {
    log_info "=========================================="
    log_info "Starting Zero-Downtime Deployment"
    log_info "Image: ${DOCKER_IMAGE}:${IMAGE_TAG}"
    log_info "=========================================="
    
    # Step 1: Pull the latest image
    log_info "Step 1: Pulling latest Docker image..."
    if ! docker pull "${DOCKER_IMAGE}:${IMAGE_TAG}"; then
        log_error "Failed to pull Docker image"
        exit 1
    fi
    log_success "Docker image pulled successfully"
    
    # Step 2: Check if old container exists
    OLD_CONTAINER_ID=""
    if is_container_running; then
        OLD_CONTAINER_ID=$(get_current_container_id)
        log_info "Found running container: ${OLD_CONTAINER_ID}"
        
        # Step 3: Rename old container
        log_info "Step 2: Renaming old container for backup..."
        docker rename "${CONTAINER_NAME}" "${CONTAINER_NAME}-old-$(date +%s)" || true
    else
        log_info "No running container found - performing fresh deployment"
    fi
    
    # Step 4: Start new container
    log_info "Step 3: Starting new container..."
    
    # Load environment variables if .env file exists
    ENV_FILE=""
    if [ -f .env ]; then
        ENV_FILE="--env-file .env"
    fi
    
    if ! docker run -d \
        --name "${CONTAINER_NAME}" \
        -p "${HOST_PORT}:${CONTAINER_PORT}" \
        ${ENV_FILE} \
        --restart unless-stopped \
        --health-cmd="curl -f http://localhost:8000/admin/login/ || exit 1" \
        --health-interval=30s \
        --health-timeout=5s \
        --health-retries=3 \
        "${DOCKER_IMAGE}:${IMAGE_TAG}"; then
        log_error "Failed to start new container"
        rollback
        exit 1
    fi
    
    log_success "New container started"
    
    # Step 5: Wait for new container to be healthy
    log_info "Step 4: Performing health check on new container..."
    sleep 10  # Give container time to start
    
    if ! wait_for_health_check; then
        log_error "New container failed health check"
        log_info "Stopping failed container..."
        docker stop "${CONTAINER_NAME}" || true
        docker rm "${CONTAINER_NAME}" || true
        rollback
        exit 1
    fi
    
    # Step 6: Stop and remove old container
    if [ -n "${OLD_CONTAINER_ID}" ]; then
        log_info "Step 5: Removing old container..."
        
        # Graceful shutdown with 30 second timeout
        log_info "Gracefully stopping old container..."
        docker stop -t 30 "${CONTAINER_NAME}-old-"* 2>/dev/null || true
        
        # Remove old containers
        log_info "Removing old containers..."
        docker rm "${CONTAINER_NAME}-old-"* 2>/dev/null || true
        
        log_success "Old container removed"
    fi
    
    # Step 7: Clean up old images
    log_info "Step 6: Cleaning up old Docker images..."
    docker image prune -f > /dev/null 2>&1 || true
    
    # Step 8: Display running container info
    log_info "=========================================="
    log_success "Deployment completed successfully!"
    log_info "=========================================="
    log_info "Container Status:"
    docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    log_info "=========================================="
    log_info "Application accessible at: http://localhost:${HOST_PORT}"
    log_info "=========================================="
}

# Trap errors and perform cleanup
trap 'log_error "Deployment failed! Check logs above for details."' ERR

# Run main function
main
