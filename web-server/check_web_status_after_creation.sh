#!/bin/bash
# Samsung Cloud Platform v2 - Web Server Status Check Script
# Server Type: WEB SERVER
# Generated: 2025-08-27
#
# PURPOSE: Check web server installation status and service health
# USAGE: Run this script directly on the WEB VM as root or rocky user
#        sudo bash checking_web_status.sh
#
# Location: /emergency_script/checking_web_status.sh

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
WEB_DIR="/home/rocky/ceweb"
NGINX_CONFIG="/etc/nginx/conf.d/creative-energy.conf"
LOGFILE="/tmp/web_status_check_$(date +%Y%m%d_%H%M%S).log"
OVERALL_STATUS=0

echo "$(cyan "==========================================")"
echo "$(cyan "WEB SERVER STATUS CHECK")"
echo "$(cyan "Samsung Cloud Platform v2")"
echo "$(cyan "==========================================")"
echo ""

# Redirect output to both console and log file
exec > >(tee -a "$LOGFILE") 2>&1

log_info "Web server status check started at $(date)"
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

# Load web server configuration
load_web_config() {
    if [[ -f "$MASTER_CONFIG" ]]; then
        NGINX_PORT=$(jq -r '.ceweb_required_variables.nginx_port // "80"' "$MASTER_CONFIG")
        PRIVATE_DOMAIN=$(jq -r '.user_input_variables.private_domain_name // "cesvc.net"' "$MASTER_CONFIG")
        PUBLIC_DOMAIN=$(jq -r '.user_input_variables.public_domain_name // "creative-energy.net"' "$MASTER_CONFIG")
        APP_PORT=$(jq -r '.ceweb_required_variables.app_server_port // "3000"' "$MASTER_CONFIG")
        APP_HOST="app.$PRIVATE_DOMAIN"
        
        log_info "Web server configuration loaded:"
        log_info "  - Nginx Port: $NGINX_PORT"
        log_info "  - Private Domain: www.$PRIVATE_DOMAIN"
        log_info "  - Public Domain: www.$PUBLIC_DOMAIN"
        log_info "  - App Backend: $APP_HOST:$APP_PORT"
        log_info "  - Web Directory: $WEB_DIR"
        return 0
    else
        log_warning "Using default web server configuration"
        NGINX_PORT="80"
        PRIVATE_DOMAIN="cesvc.net"
        PUBLIC_DOMAIN="creative-energy.net"
        APP_PORT="3000"
        APP_HOST="app.cesvc.net"
        return 1
    fi
}

# Check Nginx installation
check_nginx_installation() {
    log_info "Checking Nginx installation..."
    
    if command -v nginx >/dev/null 2>&1; then
        NGINX_VERSION=$(nginx -v 2>&1 | cut -d' ' -f3)
        log_success "Nginx found: $NGINX_VERSION"
    else
        log_error "Nginx not found"
        OVERALL_STATUS=1
        return 1
    fi
    
    # Check if systemd service exists
    if systemctl list-unit-files | grep -q "nginx.service"; then
        log_success "Nginx systemd service found"
    elif systemctl is-enabled nginx >/dev/null 2>&1 || systemctl is-active nginx >/dev/null 2>&1; then
        log_success "Nginx systemd service available"
    else
        log_error "Nginx systemd service not found or not available"
        OVERALL_STATUS=1
        return 1
    fi
    
    return 0
}

# Check Nginx service status
check_nginx_service() {
    log_info "Checking Nginx service status..."
    
    if systemctl is-active --quiet nginx; then
        log_success "Nginx service is running"
        
        # Get detailed service status
        UPTIME=$(systemctl show nginx --property=ActiveEnterTimestamp --value)
        log_info "Service uptime: $UPTIME"
        
    else
        log_error "Nginx service is not running"
        OVERALL_STATUS=1
        
        # Show service status for debugging
        log_info "Service status details:"
        systemctl status nginx --no-pager || true
        return 1
    fi
    
    return 0
}

# Check Nginx port binding
check_port_binding() {
    log_info "Checking Nginx port binding..."
    
    if netstat -tlnp 2>/dev/null | grep -q ":$NGINX_PORT "; then
        PORT_INFO=$(netstat -tlnp 2>/dev/null | grep ":$NGINX_PORT " | head -1)
        log_success "Nginx is listening on port $NGINX_PORT"
        log_info "Port info: $PORT_INFO"
    else
        log_error "Nginx is not listening on port $NGINX_PORT"
        log_info "Currently listening ports:"
        netstat -tlnp 2>/dev/null | grep nginx || log_warning "No nginx processes found listening"
        OVERALL_STATUS=1
        return 1
    fi
    
    return 0
}

# Check Nginx configuration files
check_nginx_config() {
    log_info "Checking Nginx configuration..."
    
    # Test nginx configuration syntax
    if nginx -t >/dev/null 2>&1; then
        log_success "Nginx configuration syntax is valid"
    else
        log_error "Nginx configuration syntax errors found:"
        nginx -t
        OVERALL_STATUS=1
        return 1
    fi
    
    # Check if creative-energy.conf exists
    if [[ -f "$NGINX_CONFIG" ]]; then
        log_success "Application Nginx config found: $NGINX_CONFIG"
        
        # Check key configuration elements
        if grep -q "server_name.*$PRIVATE_DOMAIN" "$NGINX_CONFIG"; then
            log_success "Private domain configuration found"
        else
            log_warning "Private domain not found in configuration"
        fi
        
        if grep -q "proxy_pass.*$APP_HOST" "$NGINX_CONFIG"; then
            log_success "App server proxy configuration found"
        else
            log_warning "App server proxy configuration not found"
        fi
        
    else
        log_warning "Application Nginx config not found: $NGINX_CONFIG"
    fi
    
    return 0
}

# Check web directory structure
check_web_directory() {
    log_info "Checking web directory structure..."
    
    if [[ ! -d "$WEB_DIR" ]]; then
        log_error "Web directory not found: $WEB_DIR"
        OVERALL_STATUS=1
        return 1
    fi
    
    log_success "Web directory exists: $WEB_DIR"
    
    # Check directory permissions
    WEB_DIR_PERMS=$(stat -c "%a" "$WEB_DIR")
    if [[ "$WEB_DIR_PERMS" -ge "755" ]]; then
        log_success "Web directory has correct permissions ($WEB_DIR_PERMS)"
    else
        log_warning "Web directory permissions may be insufficient: $WEB_DIR_PERMS"
    fi
    
    # Check /home/rocky permissions (required for nginx access)
    ROCKY_PERMS=$(stat -c "%a" "/home/rocky")
    if [[ "$ROCKY_PERMS" -ge "755" ]]; then
        log_success "Rocky home directory has correct permissions ($ROCKY_PERMS)"
    else
        log_warning "Rocky home directory permissions may block nginx access: $ROCKY_PERMS"
    fi
    
    # Check important subdirectories
    local directories_to_check=(
        "$WEB_DIR/media"
        "$WEB_DIR/files"
        "$WEB_DIR/media/img"
        "$WEB_DIR/files/audition"
    )
    
    for dir in "${directories_to_check[@]}"; do
        if [[ -d "$dir" ]]; then
            log_success "Found directory: $(basename "$dir")"
        else
            log_info "Directory not found: $(basename "$dir")"
        fi
    done
    
    return 0
}

# Test web server connectivity
test_web_connectivity() {
    log_info "Testing web server connectivity..."
    
    # Test basic connectivity
    if timeout 3 bash -c "</dev/tcp/localhost/$NGINX_PORT" >/dev/null 2>&1; then
        log_success "Web server port ($NGINX_PORT) is accessible"
    elif command -v nc >/dev/null 2>&1 && nc -z localhost "$NGINX_PORT" 2>/dev/null; then
        log_success "Web server port ($NGINX_PORT) is accessible"
    else
        log_warning "Cannot test port connectivity directly"
    fi
    
    # Test HTTP response
    if command -v curl >/dev/null 2>&1; then
        log_info "Testing HTTP responses..."
        
        # Test root endpoint
        if curl -I -s --connect-timeout 5 "http://localhost:$NGINX_PORT/" >/dev/null 2>&1; then
            log_success "Root endpoint responding"
            
            # Get response details
            HTTP_STATUS=$(curl -I -s --connect-timeout 5 "http://localhost:$NGINX_PORT/" | head -1 | awk '{print $2}')
            log_info "HTTP Status: $HTTP_STATUS"
        else
            log_warning "Root endpoint not responding"
        fi
        
        # Test health endpoint (proxy to app server)
        if curl -s --connect-timeout 5 "http://localhost:$NGINX_PORT/health" >/dev/null 2>&1; then
            log_success "Health endpoint (proxy) responding"
        else
            log_warning "Health endpoint (proxy) not responding - app server may be down"
        fi
        
    else
        log_warning "curl not available for HTTP testing"
    fi
}

# Check app server connectivity from web server
check_app_server_connectivity() {
    log_info "Checking app server connectivity from web server..."
    
    if command -v nc >/dev/null 2>&1; then
        if nc -z "$APP_HOST" "$APP_PORT" 2>/dev/null; then
            log_success "App server ($APP_HOST:$APP_PORT) is reachable from web server"
        else
            log_error "App server ($APP_HOST:$APP_PORT) is not reachable from web server"
            OVERALL_STATUS=1
        fi
    else
        if timeout 3 bash -c "</dev/tcp/$APP_HOST/$APP_PORT" >/dev/null 2>&1; then
            log_success "App server ($APP_HOST:$APP_PORT) is reachable from web server"
        else
            log_warning "Cannot test app server connectivity (network tools not available)"
        fi
    fi
    
    # Test app server health endpoint directly
    if command -v curl >/dev/null 2>&1; then
        log_info "Testing app server health endpoint directly..."
        if curl -s --connect-timeout 5 "http://$APP_HOST:$APP_PORT/health" >/dev/null 2>&1; then
            log_success "App server health endpoint responding directly"
        else
            log_warning "App server health endpoint not responding directly"
        fi
    fi
}

# Check SELinux configuration
check_selinux_config() {
    log_info "Checking SELinux configuration..."
    
    if command -v getenforce >/dev/null 2>&1; then
        SELINUX_STATUS=$(getenforce)
        log_info "SELinux status: $SELINUX_STATUS"
        
        if [[ "$SELINUX_STATUS" != "Disabled" ]]; then
            # Check important SELinux booleans for web server
            if command -v getsebool >/dev/null 2>&1; then
                local booleans=(
                    "httpd_read_user_content"
                    "httpd_can_network_connect"
                    "httpd_enable_homedirs"
                    "httpd_use_nfs"
                )
                
                for boolean in "${booleans[@]}"; do
                    if getsebool "$boolean" >/dev/null 2>&1; then
                        BOOL_STATUS=$(getsebool "$boolean" | awk '{print $3}')
                        if [[ "$BOOL_STATUS" == "on" ]]; then
                            log_success "SELinux boolean $boolean: $BOOL_STATUS"
                        else
                            log_warning "SELinux boolean $boolean: $BOOL_STATUS (may need to be enabled)"
                        fi
                    fi
                done
            fi
        fi
    else
        log_info "SELinux tools not available"
    fi
}

# Check system resources
check_system_resources() {
    log_info "Checking system resources..."
    
    # Check memory
    MEMORY_INFO=$(free -h | grep "Mem:")
    log_info "Memory usage: $MEMORY_INFO"
    
    # Check disk space for web directory
    if [[ -d "$WEB_DIR" ]]; then
        DISK_INFO=$(df -h "$WEB_DIR" | tail -1)
        log_info "Web directory disk usage: $DISK_INFO"
    fi
    
    # Check load average
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}')
    log_info "System load average:$LOAD_AVG"
    
    # Check nginx processes
    NGINX_PROCESSES=$(pgrep nginx | wc -l)
    log_info "Nginx processes running: $NGINX_PROCESSES"
    
    if [[ "$NGINX_PROCESSES" -gt 0 ]]; then
        log_info "Nginx process details:"
        ps aux | grep -E "PID|nginx" | grep -v grep || true
    fi
}

# Check logs
check_logs() {
    log_info "Checking web server logs..."
    
    # Check nginx access log
    if [[ -f "/var/log/nginx/access.log" ]]; then
        ACCESS_LOG_SIZE=$(wc -l < /var/log/nginx/access.log)
        log_info "Nginx access log: $ACCESS_LOG_SIZE lines"
        
        # Show recent access log entries
        log_info "Recent access log entries (last 3):"
        tail -3 /var/log/nginx/access.log 2>/dev/null || log_info "No recent entries found"
    else
        log_warning "Nginx access log not found"
    fi
    
    # Check nginx error log
    if [[ -f "/var/log/nginx/error.log" ]]; then
        ERROR_LOG_SIZE=$(wc -l < /var/log/nginx/error.log)
        log_info "Nginx error log: $ERROR_LOG_SIZE lines"
        
        # Check for recent errors
        if [[ "$ERROR_LOG_SIZE" -gt 0 ]]; then
            RECENT_ERRORS=$(tail -10 /var/log/nginx/error.log | wc -l)
            if [[ "$RECENT_ERRORS" -gt 0 ]]; then
                log_warning "Found $RECENT_ERRORS recent error log entries"
                log_info "Recent error log entries (last 3):"
                tail -3 /var/log/nginx/error.log 2>/dev/null || true
            fi
        fi
    else
        log_warning "Nginx error log not found"
    fi
    
    # Check system logs for nginx errors
    if command -v journalctl >/dev/null 2>&1; then
        RECENT_NGINX_ERRORS=$(journalctl --since "1 hour ago" -u nginx --no-pager | grep -i error | wc -l)
        if [[ "$RECENT_NGINX_ERRORS" -gt 0 ]]; then
            log_warning "Found $RECENT_NGINX_ERRORS recent nginx system log errors"
        fi
    fi
}

# Generate summary report
generate_summary() {
    echo ""
    echo "$(cyan "==========================================")"
    echo "$(cyan "WEB SERVER STATUS SUMMARY")"
    echo "$(cyan "==========================================")"
    echo ""
    
    if [[ $OVERALL_STATUS -eq 0 ]]; then
        log_success "🎉 WEB SERVER IS HEALTHY"
        echo ""
        log_info "All critical checks passed successfully:"
        log_info "✓ Nginx is installed and running"
        log_info "✓ Web server is listening on port $NGINX_PORT"
        log_info "✓ Configuration files are valid and present"
        log_info "✓ Directory structure and permissions are correct"
        log_info "✓ App server connectivity is working"
    else
        log_error "❌ WEB SERVER HAS ISSUES"
        echo ""
        log_error "Some critical checks failed. Please review the errors above."
        log_info "Consider running the emergency recovery script if needed:"
        log_info "sudo bash emergency_web.sh"
    fi
    
    echo ""
    log_info "Detailed log saved to: $LOGFILE"
    echo ""
    
    echo "$(yellow "Quick Manual Tests:")"
    echo "1. Check Nginx status:"
    echo "   systemctl status nginx"
    echo ""
    echo "2. Test web server response:"
    echo "   curl -I http://localhost:$NGINX_PORT/"
    echo ""
    echo "3. Test health endpoint:"
    echo "   curl http://localhost:$NGINX_PORT/health"
    echo ""
    echo "4. Check Nginx configuration:"
    echo "   nginx -t"
    echo ""
    echo "5. View Nginx logs:"
    echo "   tail -f /var/log/nginx/access.log"
    echo "   tail -f /var/log/nginx/error.log"
    echo ""
    echo "6. Check app server connectivity:"
    echo "   curl http://$APP_HOST:$APP_PORT/health"
    echo ""
    echo "7. Restart Nginx if needed:"
    echo "   sudo systemctl restart nginx"
    echo ""
}

# Main execution
main() {
    local config_ok=true
    
    # Check configuration (but don't exit if missing)
    if ! check_config; then
        config_ok=false
    fi
    
    # Load web server configuration
    load_web_config
    
    echo ""
    log_info "Running web server health checks..."
    echo ""
    
    # Run all checks
    check_nginx_installation
    check_nginx_service
    check_port_binding
    check_nginx_config
    check_web_directory
    test_web_connectivity
    check_app_server_connectivity
    check_selinux_config
    check_system_resources
    check_logs
    
    # Generate final report
    generate_summary
    
    # Set exit code based on overall status
    exit $OVERALL_STATUS
}

# Run main function
main "$@"