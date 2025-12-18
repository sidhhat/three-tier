#!/bin/bash

################################################################################
# Health Check Script for Django Notes App
# Verifies application is running and responding correctly
################################################################################

set -u

# Configuration
HEALTH_URL="${HEALTH_URL:-http://localhost:8000/admin/login/}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-5}"
TIMEOUT="${TIMEOUT:-5}"
CHECK_INTERVAL="${CHECK_INTERVAL:-2}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Exit codes
EXIT_SUCCESS=0
EXIT_FAILURE=1
EXIT_DEGRADED=2

# Check Docker container status
check_container() {
    local container_name="${1:-django-notes-app}"
    
    if ! docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        echo -e "${RED}[FAIL]${NC} Container ${container_name} is not running"
        return 1
    fi
    
    # Check container health status
    local health_status=$(docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null || echo "unknown")
    
    if [ "$health_status" = "healthy" ]; then
        echo -e "${GREEN}[OK]${NC} Container ${container_name} is healthy"
        return 0
    elif [ "$health_status" = "unhealthy" ]; then
        echo -e "${RED}[FAIL]${NC} Container ${container_name} is unhealthy"
        return 1
    elif [ "$health_status" = "starting" ]; then
        echo -e "${YELLOW}[WARN]${NC} Container ${container_name} is starting"
        return 2
    else
        echo -e "${YELLOW}[WARN]${NC} Container ${container_name} health status: ${health_status}"
        return 2
    fi
}

# Check HTTP endpoint
check_http_endpoint() {
    local url="$1"
    local attempt=1
    
    echo "Checking HTTP endpoint: ${url}"
    
    while [ $attempt -le $MAX_ATTEMPTS ]; do
        echo -n "  Attempt ${attempt}/${MAX_ATTEMPTS}... "
        
        # Perform health check
        if curl -f -s -o /dev/null -m $TIMEOUT "$url"; then
            echo -e "${GREEN}OK${NC}"
            return 0
        else
            echo -e "${RED}FAIL${NC}"
        fi
        
        attempt=$((attempt + 1))
        
        if [ $attempt -le $MAX_ATTEMPTS ]; then
            sleep $CHECK_INTERVAL
        fi
    done
    
    return 1
}

# Check detailed HTTP response
check_http_detailed() {
    local url="$1"
    
    echo "Performing detailed HTTP check..."
    
    local response=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}|%{size_download}" -m $TIMEOUT "$url" 2>/dev/null)
    
    if [ -z "$response" ]; then
        echo -e "${RED}[FAIL]${NC} No response from server"
        return 1
    fi
    
    local http_code=$(echo "$response" | cut -d'|' -f1)
    local time_total=$(echo "$response" | cut -d'|' -f2)
    local size=$(echo "$response" | cut -d'|' -f3)
    
    echo "  HTTP Status: ${http_code}"
    echo "  Response Time: ${time_total}s"
    echo "  Response Size: ${size} bytes"
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
        echo -e "${GREEN}[OK]${NC} HTTP endpoint is healthy"
        return 0
    else
        echo -e "${RED}[FAIL]${NC} HTTP endpoint returned unexpected status code: ${http_code}"
        return 1
    fi
}

# Check port availability
check_port() {
    local port="${1:-8000}"
    
    echo -n "Checking if port ${port} is listening... "
    
    if netstat -tuln 2>/dev/null | grep -q ":${port} " || ss -tuln 2>/dev/null | grep -q ":${port} "; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        return 1
    fi
}

# Check system resources
check_resources() {
    echo "Checking system resources..."
    
    # Check disk space
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    echo -n "  Disk Usage: ${disk_usage}%... "
    
    if [ "$disk_usage" -lt 80 ]; then
        echo -e "${GREEN}OK${NC}"
    elif [ "$disk_usage" -lt 90 ]; then
        echo -e "${YELLOW}WARNING${NC}"
    else
        echo -e "${RED}CRITICAL${NC}"
    fi
    
    # Check memory
    local mem_available=$(free | awk 'NR==2 {printf "%.0f", $7/$2 * 100}')
    echo -n "  Available Memory: ${mem_available}%... "
    
    if [ "$mem_available" -gt 20 ]; then
        echo -e "${GREEN}OK${NC}"
    elif [ "$mem_available" -gt 10 ]; then
        echo -e "${YELLOW}WARNING${NC}"
    else
        echo -e "${RED}CRITICAL${NC}"
    fi
}

# Main health check function
main() {
    echo "=========================================="
    echo "Django Notes App - Health Check"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
    echo ""
    
    local overall_status=$EXIT_SUCCESS
    
    # Check 1: Container status
    echo "1. Container Health Check"
    if ! check_container; then
        overall_status=$EXIT_FAILURE
    fi
    echo ""
    
    # Check 2: Port availability
    echo "2. Port Availability Check"
    if ! check_port 8000; then
        overall_status=$EXIT_FAILURE
    fi
    echo ""
    
    # Check 3: HTTP endpoint (simple)
    echo "3. HTTP Endpoint Check"
    if ! check_http_endpoint "$HEALTH_URL"; then
        overall_status=$EXIT_FAILURE
    fi
    echo ""
    
    # Check 4: HTTP endpoint (detailed)
    echo "4. Detailed HTTP Check"
    if ! check_http_detailed "$HEALTH_URL"; then
        overall_status=$EXIT_FAILURE
    fi
    echo ""
    
    # Check 5: System resources
    echo "5. System Resources Check"
    check_resources
    echo ""
    
    # Summary
    echo "=========================================="
    if [ $overall_status -eq $EXIT_SUCCESS ]; then
        echo -e "${GREEN}Overall Status: HEALTHY${NC}"
        echo "All health checks passed successfully"
    elif [ $overall_status -eq $EXIT_DEGRADED ]; then
        echo -e "${YELLOW}Overall Status: DEGRADED${NC}"
        echo "Some health checks returned warnings"
    else
        echo -e "${RED}Overall Status: UNHEALTHY${NC}"
        echo "One or more health checks failed"
    fi
    echo "=========================================="
    
    exit $overall_status
}

# Parse command line arguments
while getopts "u:a:t:h" opt; do
    case $opt in
        u) HEALTH_URL="$OPTARG" ;;
        a) MAX_ATTEMPTS="$OPTARG" ;;
        t) TIMEOUT="$OPTARG" ;;
        h)
            echo "Usage: $0 [-u URL] [-a MAX_ATTEMPTS] [-t TIMEOUT]"
            echo "  -u URL          Health check URL (default: http://localhost:8000/admin/login/)"
            echo "  -a MAX_ATTEMPTS Maximum number of attempts (default: 5)"
            echo "  -t TIMEOUT      Timeout in seconds (default: 5)"
            echo "  -h              Show this help message"
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

# Run main function
main
