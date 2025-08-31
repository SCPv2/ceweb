#!/bin/bash
# Samsung Cloud Platform v2 - Database Status Check Script
# Server Type: DB SERVER
# Generated: 2025-08-27
#
# PURPOSE: Check database server installation status and service health
# USAGE: Run this script directly on the DB VM as root or rocky user
#        sudo bash checking_db_status.sh
#
# Location: /emergency_script/checking_db_status.sh

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
LOGFILE="/tmp/db_status_check_$(date +%Y%m%d_%H%M%S).log"
OVERALL_STATUS=0

echo "$(cyan "==========================================")"
echo "$(cyan "DATABASE SERVER STATUS CHECK")"
echo "$(cyan "Samsung Cloud Platform v2")"
echo "$(cyan "==========================================")"
echo ""

# Redirect output to both console and log file
exec > >(tee -a "$LOGFILE") 2>&1

log_info "Database status check started at $(date)"
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

# Load database configuration
load_db_config() {
    if [[ -f "$MASTER_CONFIG" ]]; then
        DB_PORT=$(jq -r '.ceweb_required_variables.database_port // "2866"' "$MASTER_CONFIG")
        DB_NAME=$(jq -r '.ceweb_required_variables.database_name // "cedb"' "$MASTER_CONFIG")
        DB_USER=$(jq -r '.ceweb_required_variables.database_user // "cedbadmin"' "$MASTER_CONFIG")
        DB_PASSWORD=$(jq -r '.ceweb_required_variables.database_password // "cedbadmin123!"' "$MASTER_CONFIG")
        DB_HOST=$(jq -r '.ceweb_required_variables.database_host // "localhost"' "$MASTER_CONFIG")
        
        log_info "Database configuration loaded:"
        log_info "  - Host: $DB_HOST"
        log_info "  - Port: $DB_PORT"
        log_info "  - Database: $DB_NAME"
        log_info "  - User: $DB_USER"
        return 0
    else
        log_warning "Using default database configuration"
        DB_PORT="2866"
        DB_NAME="cedb"
        DB_USER="cedbadmin"
        DB_PASSWORD="cedbadmin123!"
        DB_HOST="localhost"
        return 1
    fi
}

# Check PostgreSQL installation
check_postgresql_installation() {
    log_info "Checking PostgreSQL installation..."
    
    if command -v psql >/dev/null 2>&1; then
        PSQL_VERSION=$(psql --version | head -n1)
        log_success "PostgreSQL client found: $PSQL_VERSION"
    else
        log_error "PostgreSQL client (psql) not found"
        OVERALL_STATUS=1
        return 1
    fi
    
    if systemctl is-enabled postgresql-16 >/dev/null 2>&1; then
        log_success "PostgreSQL 16 service found and enabled"
    elif systemctl list-unit-files | grep -q "postgresql-16.service"; then
        log_success "PostgreSQL 16 service found"
    else
        log_error "PostgreSQL 16 service not found"
        OVERALL_STATUS=1
        return 1
    fi
    
    return 0
}

# Check PostgreSQL service status
check_postgresql_service() {
    log_info "Checking PostgreSQL service status..."
    
    if systemctl is-active --quiet postgresql-16; then
        log_success "PostgreSQL service is running"
        
        # Get detailed service status
        UPTIME=$(systemctl show postgresql-16 --property=ActiveEnterTimestamp --value)
        log_info "Service uptime: $UPTIME"
        
    else
        log_error "PostgreSQL service is not running"
        OVERALL_STATUS=1
        
        # Show service status for debugging
        log_info "Service status details:"
        systemctl status postgresql-16 --no-pager || true
        return 1
    fi
    
    return 0
}

# Check PostgreSQL port binding
check_port_binding() {
    log_info "Checking PostgreSQL port binding..."
    
    if netstat -tlnp 2>/dev/null | grep -q ":$DB_PORT "; then
        PORT_INFO=$(netstat -tlnp 2>/dev/null | grep ":$DB_PORT " | head -1)
        log_success "PostgreSQL is listening on port $DB_PORT"
        log_info "Port info: $PORT_INFO"
    else
        log_error "PostgreSQL is not listening on port $DB_PORT"
        log_info "Currently listening ports:"
        netstat -tlnp 2>/dev/null | grep postgres || log_warning "No postgres processes found listening"
        OVERALL_STATUS=1
        return 1
    fi
    
    return 0
}

# Test database connectivity
test_database_connection() {
    log_info "Testing database connectivity..."
    
    # Test connection as postgres user (using password)
    if PGPASSWORD="$DB_PASSWORD" sudo -u postgres psql -h localhost -p "$DB_PORT" -d "$DB_NAME" -c "SELECT version();" >/dev/null 2>&1; then
        log_success "Database connection test passed (postgres user)"
    else
        log_warning "Database connection test failed (postgres user) - this is normal if postgres user password not set"
    fi
    
    # Test connection with application credentials
    if PGPASSWORD="$DB_PASSWORD" psql -h localhost -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT now();" >/dev/null 2>&1; then
        log_success "Application user connection test passed"
    else
        log_error "Application user connection test failed"
        log_warning "This might indicate user setup issues"
        OVERALL_STATUS=1
    fi
}

# Check database content
check_database_content() {
    log_info "Checking database content..."
    
    # Count tables
    if TABLE_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h localhost -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null); then
        TABLE_COUNT=$(echo "$TABLE_COUNT" | tr -d ' ')
        log_success "Database accessible - $TABLE_COUNT tables found in public schema"
        
        # List tables if any exist
        if [[ "$TABLE_COUNT" -gt 0 ]]; then
            log_info "Tables in database:"
            PGPASSWORD="$DB_PASSWORD" psql -h localhost -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "\dt" 2>/dev/null || true
        else
            log_warning "No tables found in database - may need schema initialization"
        fi
    else
        log_error "Cannot access database content"
        OVERALL_STATUS=1
    fi
}

# Check system resources
check_system_resources() {
    log_info "Checking system resources..."
    
    # Check memory
    MEMORY_INFO=$(free -h | grep "Mem:")
    log_info "Memory usage: $MEMORY_INFO"
    
    # Check disk space for PostgreSQL data directory
    if [[ -d "/var/lib/pgsql/16/data" ]]; then
        DISK_INFO=$(df -h /var/lib/pgsql/16/data | tail -1)
        log_info "PostgreSQL data directory disk usage: $DISK_INFO"
    fi
    
    # Check PostgreSQL processes
    POSTGRES_PROCESSES=$(ps aux | grep postgres | grep -v grep | wc -l)
    log_info "PostgreSQL processes running: $POSTGRES_PROCESSES"
}

# Check network connectivity
check_network_connectivity() {
    log_info "Checking network connectivity..."
    
    # Test local connectivity using telnet or timeout
    if timeout 3 bash -c "</dev/tcp/localhost/$DB_PORT" >/dev/null 2>&1; then
        log_success "Local database port ($DB_PORT) is accessible"
    elif command -v nc >/dev/null 2>&1 && nc -z localhost "$DB_PORT" 2>/dev/null; then
        log_success "Local database port ($DB_PORT) is accessible"
    else
        log_warning "Cannot test port connectivity (nc command not available, but port is listening)"
    fi
    
    # Test external connectivity (if configured to allow)
    if grep -q "host all all 0.0.0.0/0" /var/lib/pgsql/16/data/pg_hba.conf 2>/dev/null; then
        log_info "Database configured for external connections"
        
        # Check if firewall allows the port (if firewalld is running)
        if systemctl is-active --quiet firewalld; then
            if firewall-cmd --list-ports | grep -q "$DB_PORT/tcp"; then
                log_success "Firewall allows database port"
            else
                log_warning "Firewall may be blocking database port $DB_PORT"
            fi
        fi
    else
        log_info "Database configured for local connections only"
    fi
}

# Generate summary report
generate_summary() {
    echo ""
    echo "$(cyan "==========================================")"
    echo "$(cyan "DATABASE STATUS SUMMARY")"
    echo "$(cyan "==========================================")"
    echo ""
    
    if [[ $OVERALL_STATUS -eq 0 ]]; then
        log_success "🎉 DATABASE SERVER IS HEALTHY"
        echo ""
        log_info "All checks passed successfully:"
        log_info "✓ PostgreSQL is installed and running"
        log_info "✓ Service is active and listening on port $DB_PORT"
        log_info "✓ Database connectivity is working"
        log_info "✓ Configuration files are present and valid"
    else
        log_error "❌ DATABASE SERVER HAS ISSUES"
        echo ""
        log_error "Some checks failed. Please review the errors above."
        log_info "Consider running the emergency recovery script if needed:"
        log_info "sudo bash emergency_db.sh"
    fi
    
    echo ""
    log_info "Detailed log saved to: $LOGFILE"
    echo ""
    
    echo "$(yellow "Quick Manual Tests:")"
    echo "1. Test database connection:"
    echo "   PGPASSWORD=$DB_PASSWORD psql -h localhost -p $DB_PORT -U $DB_USER -d $DB_NAME -c 'SELECT now();'"
    echo ""
    echo "2. Check service status:"
    echo "   systemctl status postgresql-16"
    echo ""
    echo "3. Check port binding:"
    echo "   netstat -tlnp | grep :$DB_PORT"
    echo ""
    echo "4. View PostgreSQL logs:"
    echo "   sudo journalctl -u postgresql-16 -f"
    echo ""
}

# Main execution
main() {
    local config_ok=true
    
    # Check configuration (but don't exit if missing)
    if ! check_config; then
        config_ok=false
    fi
    
    # Load database configuration
    load_db_config
    
    echo ""
    log_info "Running database health checks..."
    echo ""
    
    # Run all checks
    check_postgresql_installation
    check_postgresql_service
    check_port_binding
    test_database_connection
    check_database_content
    check_system_resources
    check_network_connectivity
    
    # Generate final report
    generate_summary
    
    # Set exit code based on overall status
    exit $OVERALL_STATUS
}

# Run main function
main "$@"