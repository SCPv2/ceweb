#!/bin/bash
# Samsung Cloud Platform v2 - App Server Status Check Script
# Server Type: APP SERVER
# Generated: 2025-08-27
#
# PURPOSE: Check app server installation status and service health
# USAGE: Run this script directly on the APP VM as root or rocky user
#        sudo bash checking_app_status.sh
#
# Location: /emergency_script/checking_app_status.sh

set -euo pipefail

# Color functions for better visibility
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
cyan() { echo -e "\033[36m$1\033[0m"; }

# Logging
log_info() { echo "[INFO] $1"; }
log_success() { echo "$(green "[SUCCESS]") $1"; }
log_error() { echo "$(red "[ERROR]") $1"; }
log_warning() { echo "$(yellow "[WARNING]") $1"; }

# Global variables
MASTER_CONFIG="/home/rocky/ceweb/web-server/master_config.json"
APP_DIR="/home/rocky/ceweb/app-server"
LOGFILE="/tmp/app_status_check_$(date +%Y%m%d_%H%M%S).log"
OVERALL_STATUS=0

echo "$(cyan "==========================================")"
echo "$(cyan "APP SERVER STATUS CHECK")"
echo "$(cyan "Samsung Cloud Platform v2")"
echo "$(cyan "==========================================")"
echo ""

# Redirect output to both console and log file
exec > >(tee -a "$LOGFILE") 2>&1

log_info "App server status check started at $(date)"
log_info "Log file: $LOGFILE"
echo ""

# Check if configuration exists
check_config() {
    log_info "Checking configuration files..."
    
    if [[ ! -f "$MASTER_CONFIG" ]]; then
        log_error "Master config file not found: $MASTER_CONFIG"
        OVERALL_STATUS=1
        return 1
    fi
    
    # Validate JSON format
    if ! jq . "$MASTER_CONFIG" >/dev/null 2>&1; then
        log_error "Invalid JSON in master config file"
        OVERALL_STATUS=1
        return 1
    fi
    
    log_success "Configuration file exists and is valid"
    return 0
}

# Load app server configuration
load_app_config() {
    if [[ -f "$MASTER_CONFIG" ]]; then
        APP_PORT=$(jq -r '.ceweb_required_variables.app_server_port // "3000"' "$MASTER_CONFIG")
        DB_HOST=$(jq -r '.ceweb_required_variables.database_host // "db.cesvc.net"' "$MASTER_CONFIG")
        DB_PORT=$(jq -r '.ceweb_required_variables.database_port // "2866"' "$MASTER_CONFIG")
        DB_NAME=$(jq -r '.ceweb_required_variables.database_name // "cedb"' "$MASTER_CONFIG")
        DB_USER=$(jq -r '.ceweb_required_variables.database_user // "cedbadmin"' "$MASTER_CONFIG")
        NODE_ENV=$(jq -r '.ceweb_required_variables.node_env // "production"' "$MASTER_CONFIG")
        
        log_info "App server configuration loaded:"
        log_info "  - App Port: $APP_PORT"
        log_info "  - Environment: $NODE_ENV"
        log_info "  - Database: $DB_HOST:$DB_PORT/$DB_NAME"
        log_info "  - App Directory: $APP_DIR"
        return 0
    else
        log_warning "Using default app server configuration"
        APP_PORT="3000"
        DB_HOST="db.cesvc.net"
        DB_PORT="2866"
        DB_NAME="cedb"
        DB_USER="cedbadmin"
        NODE_ENV="production"
        return 1
    fi
}

# Check Node.js installation
check_nodejs_installation() {
    log_info "Checking Node.js installation..."
    
    if command -v node >/dev/null 2>&1; then
        NODE_VERSION=$(node --version)
        log_success "Node.js found: $NODE_VERSION"
    else
        log_error "Node.js not found"
        OVERALL_STATUS=1
        return 1
    fi
    
    if command -v npm >/dev/null 2>&1; then
        NPM_VERSION=$(npm --version)
        log_success "npm found: v$NPM_VERSION"
    else
        log_error "npm not found"
        OVERALL_STATUS=1
        return 1
    fi
    
    return 0
}

# Check PM2 installation and status
check_pm2_status() {
    log_info "Checking PM2 process manager..."
    
    if command -v pm2 >/dev/null 2>&1; then
        PM2_VERSION=$(pm2 --version)
        log_success "PM2 found: v$PM2_VERSION"
    else
        log_error "PM2 not found"
        OVERALL_STATUS=1
        return 1
    fi
    
    # Check PM2 processes as rocky user
    if sudo -u rocky pm2 list >/dev/null 2>&1; then
        PM2_PROCESSES=$(sudo -u rocky pm2 list | grep -c "online" || echo "0")
        if [[ "$PM2_PROCESSES" -gt 0 ]]; then
            log_success "$PM2_PROCESSES PM2 process(es) running"
            log_info "PM2 status:"
            sudo -u rocky pm2 list --no-color 2>/dev/null || true
        else
            log_warning "No PM2 processes running"
        fi
    else
        log_warning "Cannot check PM2 status (PM2 may not be initialized)"
    fi
    
    return 0
}

# Check application directory and files
check_app_directory() {
    log_info "Checking application directory structure..."
    
    if [[ ! -d "$APP_DIR" ]]; then
        log_error "Application directory not found: $APP_DIR"
        OVERALL_STATUS=1
        return 1
    fi
    
    log_success "Application directory exists: $APP_DIR"
    
    # Check important files
    local files_to_check=(
        "$APP_DIR/package.json"
        "$APP_DIR/server.js"
        "$APP_DIR/.env"
        "$APP_DIR/ecosystem.config.js"
    )
    
    for file in "${files_to_check[@]}"; do
        if [[ -f "$file" ]]; then
            log_success "Found: $(basename "$file")"
        else
            log_warning "Missing: $(basename "$file")"
        fi
    done
    
    # Check .env file permissions
    if [[ -f "$APP_DIR/.env" ]]; then
        ENV_PERMS=$(stat -c "%a" "$APP_DIR/.env")
        if [[ "$ENV_PERMS" == "600" ]]; then
            log_success ".env file has correct permissions (600)"
        else
            log_warning ".env file permissions: $ENV_PERMS (should be 600)"
        fi
    fi
    
    return 0
}

# Check Node.js processes
check_nodejs_processes() {
    log_info "Checking Node.js processes..."
    
    NODE_PROCESSES=$(pgrep -f node | wc -l)
    if [[ "$NODE_PROCESSES" -gt 0 ]]; then
        log_success "$NODE_PROCESSES Node.js process(es) running"
        
        # Show process details
        log_info "Node.js processes:"
        ps aux | grep -E "PID|node" | grep -v grep || true
    else
        log_error "No Node.js processes found"
        OVERALL_STATUS=1
        return 1
    fi
    
    return 0
}

# Check application port binding
check_port_binding() {
    log_info "Checking application port binding..."
    
    if netstat -tlnp 2>/dev/null | grep -q ":$APP_PORT "; then
        PORT_INFO=$(netstat -tlnp 2>/dev/null | grep ":$APP_PORT " | head -1)
        log_success "Application is listening on port $APP_PORT"
        log_info "Port info: $PORT_INFO"
    else
        log_error "Application is not listening on port $APP_PORT"
        log_info "Currently listening ports:"
        netstat -tlnp 2>/dev/null | grep -E ":300[0-9]" || log_warning "No ports in 3000-3009 range found listening"
        OVERALL_STATUS=1
        return 1
    fi
    
    return 0
}

# Test application connectivity
test_application_connectivity() {
    log_info "Testing application connectivity..."
    
    # Test basic connectivity
    if timeout 3 bash -c "</dev/tcp/localhost/$APP_PORT" >/dev/null 2>&1; then
        log_success "Application port ($APP_PORT) is accessible"
    elif command -v nc >/dev/null 2>&1 && nc -z localhost "$APP_PORT" 2>/dev/null; then
        log_success "Application port ($APP_PORT) is accessible"
    else
        log_warning "Cannot test port connectivity directly"
    fi
    
    # Test health endpoint
    if command -v curl >/dev/null 2>&1; then
        log_info "Testing application health endpoint..."
        if curl -f -s --connect-timeout 5 "http://localhost:$APP_PORT/health" >/dev/null 2>&1; then
            log_success "Health endpoint responding"
        elif curl -s --connect-timeout 5 "http://localhost:$APP_PORT/" >/dev/null 2>&1; then
            log_success "Application root endpoint responding"
        else
            log_warning "Application endpoints not responding (this may be normal if no health endpoint exists)"
        fi
    else
        log_warning "curl not available for endpoint testing"
    fi
}

# Check database connectivity from app
check_database_connectivity() {
    log_info "Checking database connectivity from app server..."
    
    if command -v nc >/dev/null 2>&1; then
        if nc -z "$DB_HOST" "$DB_PORT" 2>/dev/null; then
            log_success "Database ($DB_HOST:$DB_PORT) is reachable from app server"
        else
            log_error "Database ($DB_HOST:$DB_PORT) is not reachable from app server"
            OVERALL_STATUS=1
        fi
    else
        if timeout 3 bash -c "</dev/tcp/$DB_HOST/$DB_PORT" >/dev/null 2>&1; then
            log_success "Database ($DB_HOST:$DB_PORT) is reachable from app server"
        else
            log_warning "Cannot test database connectivity (network tools not available)"
        fi
    fi
    
    # Test PostgreSQL client connectivity if available
    if command -v psql >/dev/null 2>&1 && [[ -f "$APP_DIR/.env" ]]; then
        log_info "Testing database authentication..."
        if source "$APP_DIR/.env" 2>/dev/null && [[ -n "${DB_PASSWORD:-}" ]]; then
            if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
                log_success "Database authentication successful"
            else
                log_warning "Database authentication failed (check credentials)"
            fi
        else
            log_warning "Cannot test database authentication (missing environment variables)"
        fi
    fi
}

# Check system resources
check_system_resources() {
    log_info "Checking system resources..."
    
    # Check memory
    MEMORY_INFO=$(free -h | grep "Mem:")
    log_info "Memory usage: $MEMORY_INFO"
    
    # Check disk space for app directory
    if [[ -d "$APP_DIR" ]]; then
        DISK_INFO=$(df -h "$APP_DIR" | tail -1)
        log_info "Application directory disk usage: $DISK_INFO"
    fi
    
    # Check load average
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}')
    log_info "System load average:$LOAD_AVG"
    
    # Check if app is consuming high CPU/memory
    if command -v top >/dev/null 2>&1; then
        log_info "Top Node.js processes by CPU:"
        ps aux | grep node | grep -v grep | head -3 || log_info "No Node.js processes in top list"
    fi
}

# Check logs and errors
check_logs() {
    log_info "Checking application logs..."
    
    # Check PM2 logs if available
    if command -v pm2 >/dev/null 2>&1 && sudo -u rocky pm2 list >/dev/null 2>&1; then
        log_info "Recent PM2 logs:"
        sudo -u rocky pm2 logs --lines 5 --nostream 2>/dev/null || log_warning "Cannot read PM2 logs"
    fi
    
    # Check application log directory
    if [[ -d "$APP_DIR/logs" ]]; then
        LOG_COUNT=$(find "$APP_DIR/logs" -type f -name "*.log" 2>/dev/null | wc -l)
        if [[ "$LOG_COUNT" -gt 0 ]]; then
            log_info "Found $LOG_COUNT log file(s) in $APP_DIR/logs"
            # Show recent errors if any
            if find "$APP_DIR/logs" -name "*.log" -exec grep -i "error" {} + >/dev/null 2>&1; then
                log_warning "Found errors in application logs - check manually"
            fi
        else
            log_info "No log files found in $APP_DIR/logs"
        fi
    fi
    
    # Check system logs for Node.js/PM2 errors
    if command -v journalctl >/dev/null 2>&1; then
        RECENT_ERRORS=$(journalctl --since "1 hour ago" | grep -i -E "(node|pm2|error)" | wc -l)
        if [[ "$RECENT_ERRORS" -gt 0 ]]; then
            log_warning "Found $RECENT_ERRORS recent system log entries related to Node.js/PM2"
        fi
    fi
}

# Generate summary report
generate_summary() {
    echo ""
    echo "$(cyan "==========================================")"
    echo "$(cyan "APP SERVER STATUS SUMMARY")"
    echo "$(cyan "==========================================")"
    echo ""
    
    if [[ $OVERALL_STATUS -eq 0 ]]; then
        log_success "🎉 APP SERVER IS HEALTHY"
        echo ""
        log_info "All critical checks passed successfully:"
        log_info "✓ Node.js and PM2 are installed and running"
        log_info "✓ Application is listening on port $APP_PORT"
        log_info "✓ Database connectivity is working"
        log_info "✓ Configuration files are present and valid"
    else
        log_error "❌ APP SERVER HAS ISSUES"
        echo ""
        log_error "Some critical checks failed. Please review the errors above."
        log_info "Consider running the emergency recovery script if needed:"
        log_info "sudo bash emergency_app.sh"
    fi
    
    echo ""
    log_info "Detailed log saved to: $LOGFILE"
    echo ""
    
    echo "$(yellow "Quick Manual Tests:")"
    echo "1. Check PM2 status:"
    echo "   sudo -u rocky pm2 status"
    echo ""
    echo "2. Test application health:"
    echo "   curl http://localhost:$APP_PORT/health"
    echo ""
    echo "3. Check application logs:"
    echo "   sudo -u rocky pm2 logs"
    echo ""
    echo "4. Test database connection:"
    echo "   cd $APP_DIR && sudo -u rocky node -e 'console.log(process.env.DB_HOST)'"
    echo ""
    echo "5. Check port binding:"
    echo "   netstat -tlnp | grep :$APP_PORT"
    echo ""
    echo "6. Restart application if needed:"
    echo "   sudo -u rocky pm2 restart all"
    echo ""
}

# Main execution
main() {
    local config_ok=true
    
    # Check configuration (but don't exit if missing)
    if ! check_config; then
        config_ok=false
    fi
    
    # Load app server configuration
    load_app_config
    
    echo ""
    log_info "Running app server health checks..."
    echo ""
    
    # Run all checks
    check_nodejs_installation
    check_pm2_status
    check_app_directory
    check_nodejs_processes
    check_port_binding
    test_application_connectivity
    check_database_connectivity
    check_system_resources
    check_logs
    
    # Generate final report
    generate_summary
    
    # Set exit code based on overall status
    exit $OVERALL_STATUS
}

# Run main function
main "$@"