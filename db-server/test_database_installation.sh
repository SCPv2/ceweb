#!/bin/bash

# Database Installation Test Script
# Creative Energy Database Verification
# Tests both local and remote PostgreSQL installations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration variables
DB_HOST="${DB_HOST:-db.cesvc.net}"
DB_PORT="${DB_PORT:-2866}"
DB_NAME="${DB_NAME:-cedb}"
DB_USER="${DB_USER:-ceadmin}"
DB_ADMIN="${DB_ADMIN:-postgres}"

# Test mode: local or remote
TEST_MODE=""
PASSWORD=""

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE} Creative Energy Database Test Suite${NC}"
echo -e "${BLUE}============================================${NC}"

# Function to print colored output
print_test_header() {
    echo
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_failure() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Function to select test mode
select_test_mode() {
    echo "Select test mode:"
    echo "1) Local PostgreSQL installation test"
    echo "2) Remote PostgreSQL connection test"
    echo "3) Full test suite (both local and remote)"
    echo
    read -p "Enter your choice (1-3): " choice
    
    case $choice in
        1)
            TEST_MODE="local"
            DB_HOST="localhost"
            ;;
        2)
            TEST_MODE="remote"
            ;;
        3)
            TEST_MODE="full"
            ;;
        *)
            print_failure "Invalid choice"
            exit 1
            ;;
    esac
}

# Function to get password
get_password() {
    while [ -z "$PASSWORD" ]; do
        read -s -p "Enter password for user '$DB_USER': " PASSWORD
        echo
    done
}

# Test 1: PostgreSQL Service Status
test_service_status() {
    print_test_header "Test 1: PostgreSQL Service Status"
    
    if [ "$TEST_MODE" = "local" ] || [ "$TEST_MODE" = "full" ]; then
        if systemctl is-active --quiet postgresql-16; then
            print_success "PostgreSQL 16 service is running"
        else
            print_failure "PostgreSQL 16 service is not running"
            return 1
        fi
        
        # Check if service is enabled
        if systemctl is-enabled --quiet postgresql-16; then
            print_success "PostgreSQL 16 service is enabled for auto-start"
        else
            print_warning "PostgreSQL 16 service is not enabled for auto-start"
        fi
    else
        print_info "Skipping service status check (remote test mode)"
    fi
}

# Test 2: Network Connectivity
test_connectivity() {
    print_test_header "Test 2: Network Connectivity"
    
    if [ "$TEST_MODE" = "remote" ] || [ "$TEST_MODE" = "full" ]; then
        if nc -z "$DB_HOST" "$DB_PORT" 2>/dev/null; then
            print_success "Can connect to $DB_HOST:$DB_PORT"
        else
            print_failure "Cannot connect to $DB_HOST:$DB_PORT"
            return 1
        fi
    else
        if nc -z localhost "$DB_PORT" 2>/dev/null; then
            print_success "PostgreSQL is listening on port $DB_PORT"
        else
            print_failure "PostgreSQL is not listening on port $DB_PORT"
            return 1
        fi
    fi
}

# Test 3: Database Connection
test_database_connection() {
    print_test_header "Test 3: Database Connection"
    
    if PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
        print_success "Successfully connected to database '$DB_NAME'"
    else
        print_failure "Failed to connect to database '$DB_NAME'"
        return 1
    fi
    
    # Test admin connection if available
    if [ -n "$ADMIN_PASSWORD" ]; then
        if PGPASSWORD=$ADMIN_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
            print_success "Admin connection successful"
        else
            print_warning "Admin connection failed"
        fi
    fi
}

# Test 4: Database Schema
test_schema() {
    print_test_header "Test 4: Database Schema"
    
    # Test tables
    local tables=(products inventory orders)
    for table in "${tables[@]}"; do
        if PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "\d $table" >/dev/null 2>&1; then
            print_success "Table '$table' exists"
        else
            print_failure "Table '$table' missing"
            return 1
        fi
    done
    
    # Test sequences
    local sequences=(products_id_seq inventory_id_seq orders_id_seq)
    for seq in "${sequences[@]}"; do
        if PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "\d $seq" >/dev/null 2>&1; then
            print_success "Sequence '$seq' exists"
        else
            print_failure "Sequence '$seq' missing"
            return 1
        fi
    done
    
    # Test views
    if PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "\d product_inventory_view" >/dev/null 2>&1; then
        print_success "View 'product_inventory_view' exists"
    else
        print_failure "View 'product_inventory_view' missing"
        return 1
    fi
}

# Test 5: Functions
test_functions() {
    print_test_header "Test 5: Database Functions"
    
    local functions=(process_order_inventory reset_daily_inventory update_inventory_timestamp update_products_timestamp)
    
    for func in "${functions[@]}"; do
        if PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT proname FROM pg_proc WHERE proname = '$func';" | grep -q "$func"; then
            print_success "Function '$func' exists"
        else
            print_failure "Function '$func' missing"
            return 1
        fi
    done
    
    # Test function execution
    if PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT process_order_inventory(1, 0);" >/dev/null 2>&1; then
        print_success "Function execution test passed"
    else
        print_warning "Function execution test failed (may need permissions)"
    fi
}

# Test 6: Sample Data
test_sample_data() {
    print_test_header "Test 6: Sample Data"
    
    # Test products data
    local product_count=$(PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM products;")
    if [ "$product_count" -gt 0 ]; then
        print_success "Products table contains $product_count records"
    else
        print_failure "Products table is empty"
        return 1
    fi
    
    # Test inventory data
    local inventory_count=$(PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM inventory;")
    if [ "$inventory_count" -gt 0 ]; then
        print_success "Inventory table contains $inventory_count records"
    else
        print_failure "Inventory table is empty"
        return 1
    fi
    
    # Test data integrity
    local orphan_inventory=$(PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM inventory i LEFT JOIN products p ON i.product_id = p.id WHERE p.id IS NULL;")
    if [ "$orphan_inventory" -eq 0 ]; then
        print_success "Data integrity check passed (no orphaned inventory records)"
    else
        print_failure "Data integrity check failed ($orphan_inventory orphaned inventory records)"
        return 1
    fi
}

# Test 7: Indexes and Constraints
test_indexes_constraints() {
    print_test_header "Test 7: Indexes and Constraints"
    
    # Test primary keys
    local tables=(products inventory orders)
    for table in "${tables[@]}"; do
        if PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT conname FROM pg_constraint WHERE contype='p' AND conrelid = '$table'::regclass;" | grep -q "${table}_pkey"; then
            print_success "Primary key exists for table '$table'"
        else
            print_failure "Primary key missing for table '$table'"
            return 1
        fi
    done
    
    # Test foreign keys
    if PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT conname FROM pg_constraint WHERE contype='f';" | grep -q "inventory_product_id_fkey"; then
        print_success "Foreign key 'inventory_product_id_fkey' exists"
    else
        print_failure "Foreign key 'inventory_product_id_fkey' missing"
        return 1
    fi
    
    # Test indexes
    local indexes=(idx_products_category idx_inventory_product_id idx_orders_product_id)
    for idx in "${indexes[@]}"; do
        if PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT indexname FROM pg_indexes WHERE indexname = '$idx';" | grep -q "$idx"; then
            print_success "Index '$idx' exists"
        else
            print_failure "Index '$idx' missing"
            return 1
        fi
    done
}

# Test 8: Performance Test
test_performance() {
    print_test_header "Test 8: Basic Performance Test"
    
    # Test simple query performance
    local start_time=$(date +%s%N)
    PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT COUNT(*) FROM product_inventory_view;" >/dev/null
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    if [ $duration -lt 1000 ]; then
        print_success "Query performance test passed (${duration}ms)"
    else
        print_warning "Query performance test slow (${duration}ms)"
    fi
    
    # Test concurrent connections (simple test)
    local connection_limit=$(PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SHOW max_connections;")
    print_info "Maximum connections configured: $connection_limit"
}

# Test 9: Application Integration
test_application_integration() {
    print_test_header "Test 9: Application Integration Test"
    
    # Test view query (typical application query)
    if PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT id, title, stock_display FROM product_inventory_view WHERE category = 'bigboys' LIMIT 1;" >/dev/null 2>&1; then
        print_success "Product inventory view query successful"
    else
        print_failure "Product inventory view query failed"
        return 1
    fi
    
    # Test order simulation
    if PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT process_order_inventory(1, 1);" >/dev/null 2>&1; then
        print_success "Order processing function test passed"
    else
        print_warning "Order processing function test failed (check permissions)"
    fi
    
    # Test data aggregation (typical for analytics)
    if PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT category, COUNT(*), SUM(price_numeric) FROM products GROUP BY category;" >/dev/null 2>&1; then
        print_success "Data aggregation query successful"
    else
        print_failure "Data aggregation query failed"
        return 1
    fi
}

# Test 10: Security Test
test_security() {
    print_test_header "Test 10: Security Configuration"
    
    # Test connection from unauthorized user (should fail)
    if PGPASSWORD="wrong_password" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
        print_failure "Security test failed - accepts wrong password"
        return 1
    else
        print_success "Password authentication working correctly"
    fi
    
    # Check if superuser access is restricted
    local is_superuser=$(PGPASSWORD=$PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT usesuper FROM pg_user WHERE usename = '$DB_USER';")
    if [ "$is_superuser" = "f" ]; then
        print_success "Application user is not a superuser (good security practice)"
    else
        print_warning "Application user has superuser privileges (security risk)"
    fi
}

# Summary function
print_summary() {
    echo
    print_test_header "Test Summary"
    
    local total_tests=10
    local passed_tests=$((total_tests - failed_tests))
    
    if [ $failed_tests -eq 0 ]; then
        print_success "All tests passed! Database installation is verified."
        echo -e "${GREEN}Status: ✓ READY FOR PRODUCTION${NC}"
    elif [ $failed_tests -le 2 ]; then
        print_warning "$passed_tests/$total_tests tests passed. Minor issues detected."
        echo -e "${YELLOW}Status: ⚠ NEEDS ATTENTION${NC}"
    else
        print_failure "$passed_tests/$total_tests tests passed. Major issues detected."
        echo -e "${RED}Status: ✗ REQUIRES FIXES${NC}"
    fi
    
    echo
    echo -e "${BLUE}Database Configuration:${NC}"
    echo "  Host: $DB_HOST"
    echo "  Port: $DB_PORT" 
    echo "  Database: $DB_NAME"
    echo "  User: $DB_USER"
    echo
}

# Main execution
main() {
    select_test_mode
    get_password
    
    print_info "Starting database tests with mode: $TEST_MODE"
    print_info "Target: $DB_HOST:$DB_PORT/$DB_NAME"
    
    # Initialize counters
    failed_tests=0
    
    # Run tests
    test_service_status || ((failed_tests++))
    test_connectivity || ((failed_tests++))
    test_database_connection || ((failed_tests++))
    test_schema || ((failed_tests++))
    test_functions || ((failed_tests++))
    test_sample_data || ((failed_tests++))
    test_indexes_constraints || ((failed_tests++))
    test_performance || ((failed_tests++))
    test_application_integration || ((failed_tests++))
    test_security || ((failed_tests++))
    
    print_summary
    
    # Exit with error if tests failed
    if [ $failed_tests -gt 0 ]; then
        exit 1
    fi
}

# Check prerequisites
if ! command -v psql &> /dev/null; then
    print_failure "PostgreSQL client (psql) is not installed"
    exit 1
fi

if ! command -v nc &> /dev/null; then
    print_warning "netcat (nc) is not installed - network tests may be limited"
fi

# Run main function
main "$@"