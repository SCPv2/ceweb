#!/bin/bash
# ==============================================================================
# Copyright (c) 2025 Stan H. All rights reserved.
#
# This software and its source code are the exclusive property of Stan H.
#
# Use is strictly limited to 2025 SCPv2 Advance training and education only.
# Any reproduction, modification, distribution, or other use beyond this scope is
# strictly prohibited without prior written permission from the copyright holder.
#
# Unauthorized use may lead to legal action under applicable law.
#
# Contact: ars4mundus@gmail.com
# ==============================================================================

# Creative Energy DBaaS Database Setup Script
# Target: db.your_private_domain_name.net:2866, Database: cedb, User: ceadmin
# Execute from: app.your_private_domain_name.net (app-server)
# Purpose: Complete database schema setup for DBaaS PostgreSQL server

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration - DBaaS Database Connection
DB_HOST="db.your_private_domain_name.net"
DB_PORT="2866"
DB_NAME="cedb"
DB_USER="ceadmin"
DB_PASSWORD="ceadmin123!"
SCHEMA_FILE="./postgresql_dbaas_init_schema.sql"

# App Server Configuration
APP_SERVER_HOST="app.your_private_domain_name.net"
APP_SERVER_PORT="3000"

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE} Creative Energy DBaaS Database Setup Script${NC}"
echo -e "${BLUE} Target Database: ${DB_HOST}:${DB_PORT}/${DB_NAME}${NC}"
echo -e "${BLUE} App Server: ${APP_SERVER_HOST}:${APP_SERVER_PORT}${NC}"
echo -e "${BLUE} Execution Host: $(hostname)${NC}"
echo -e "${BLUE}================================================================${NC}"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

print_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_step "Step 1: Checking prerequisites..."
    
    # Check if psql is installed
    if ! command -v psql &> /dev/null; then
        print_error "PostgreSQL client (psql) is not installed"
        echo "Install it with:"
        echo "  CentOS/Rocky Linux: sudo dnf install postgresql"
        echo "  Ubuntu/Debian: sudo apt-get install postgresql-client"
        exit 1
    fi
    
    local psql_version=$(psql --version 2>/dev/null | head -n 1)
    print_status "PostgreSQL client found: $psql_version"
    
    # Check if schema file exists
    if [ ! -f "$SCHEMA_FILE" ]; then
        print_error "Schema file $SCHEMA_FILE not found!"
        print_error "Please ensure postgresql_dbaas_init_schema.sql is in the current directory"
        exit 1
    fi
    
    print_status "Schema file found: $SCHEMA_FILE"
    print_success "Prerequisites check completed"
}

# Function to test database connection
test_connection() {
    print_step "Step 2: Testing database connection..."
    
    print_status "Connecting to $DB_HOST:$DB_PORT as $DB_USER..."
    
    # Test connection with credentials
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 'Connection successful!' as status, current_timestamp as connected_at;" >/dev/null 2>&1; then
        print_success "Database connection established successfully"
        
        # Get database information
        local db_info=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT current_database() || ' on ' || version();" 2>/dev/null)
        print_status "Database info: $db_info"
        
    else
        print_error "Failed to connect to database"
        print_error "Please verify:"
        print_error "1. Database server is running: systemctl status postgresql-16"
        print_error "2. Firewall allows connection: firewall-cmd --list-ports"
        print_error "3. PostgreSQL configuration allows remote connections"
        print_error "4. Credentials are correct: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
        exit 1
    fi
}

# Function to check existing schema
check_existing_schema() {
    print_step "Step 3: Checking existing database schema..."
    
    # Check if tables already exist
    local existing_tables=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "
        SELECT string_agg(table_name, ', ') 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name IN ('products', 'inventory', 'orders');
    " 2>/dev/null || echo "")
    
    if [ -n "$existing_tables" ]; then
        print_warning "Existing Creative Energy tables found: $existing_tables"
        
        # Ask user if they want to continue
        echo -n "Do you want to continue? This will update/recreate the schema [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_status "Installation cancelled by user"
            exit 0
        fi
        
        print_status "Proceeding with schema update..."
    else
        print_status "No existing Creative Energy tables found. Proceeding with fresh installation."
    fi
}

# Function to install database schema
install_schema() {
    print_step "Step 4: Installing database schema and initial data..."
    
    print_status "Executing schema file: $SCHEMA_FILE"
    
    # Execute schema file
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE"; then
        print_success "Database schema installation completed"
    else
        print_error "Schema installation failed"
        exit 1
    fi
}

# Function to verify installation
verify_installation() {
    print_step "Step 5: Verifying installation..."
    
    # Check tables
    local table_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "
        SELECT COUNT(*) 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name IN ('products', 'inventory', 'orders');
    " 2>/dev/null || echo "0")
    
    if [ "$table_count" = "3" ]; then
        print_success "All 3 main tables created successfully"
        
        # Show table details
        echo -e "${BLUE}Created tables:${NC}"
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
            SELECT 
                table_name as \"Table Name\",
                (SELECT count(*) FROM information_schema.columns WHERE table_name = t.table_name) as \"Columns\"
            FROM information_schema.tables t
            WHERE table_schema = 'public' 
            AND table_name IN ('products', 'inventory', 'orders')
            ORDER BY table_name;
        "
        
    else
        print_error "Table creation verification failed. Expected 3 tables, found $table_count"
        exit 1
    fi
    
    # Check sample data
    local products_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM products;" 2>/dev/null || echo "0")
    local inventory_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM inventory;" 2>/dev/null || echo "0")
    
    if [ "$products_count" -gt 0 ] && [ "$inventory_count" -gt 0 ]; then
        print_success "Initial data verified: $products_count products, $inventory_count inventory records"
        
        # Show sample products
        echo -e "${BLUE}Sample products:${NC}"
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
            SELECT 
                id, 
                LEFT(title, 40) as title, 
                category, 
                price,
                stock_quantity
            FROM product_inventory_view 
            ORDER BY id 
            LIMIT 5;
        "
        
    else
        print_warning "Initial data verification failed or incomplete"
        print_warning "Products: $products_count, Inventory: $inventory_count"
    fi
    
    # Check functions
    local functions_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "
        SELECT COUNT(*) 
        FROM information_schema.routines 
        WHERE routine_schema = 'public' 
        AND routine_name LIKE '%inventory%';
    " 2>/dev/null || echo "0")
    
    print_status "Custom functions created: $functions_count"
    
    # Check views
    local views_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "
        SELECT COUNT(*) 
        FROM information_schema.views 
        WHERE table_schema = 'public';
    " 2>/dev/null || echo "0")
    
    print_status "Views created: $views_count"
}

# Function to test application-level operations
test_application_operations() {
    print_step "Step 6: Testing application-level operations..."
    
    # Test product inventory view
    print_status "Testing product inventory view..."
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 'Product inventory view test' as test_type, COUNT(*) as records 
        FROM product_inventory_view;
    " >/dev/null 2>&1; then
        print_success "Product inventory view test passed"
    else
        print_error "Product inventory view test failed"
    fi
    
    # Test inventory functions (read-only test)
    print_status "Testing inventory management functions..."
    local function_exists=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "
        SELECT COUNT(*) 
        FROM information_schema.routines 
        WHERE routine_name = 'process_order_inventory';
    " 2>/dev/null || echo "0")
    
    if [ "$function_exists" -gt 0 ]; then
        print_success "Inventory management functions are available"
    else
        print_warning "Inventory management functions not found"
    fi
}

# Function to create app server environment file
create_app_env_file() {
    print_step "Step 7: Creating app server environment configuration..."
    
    local env_file=".env.app_server"
    
    print_status "Creating environment file: $env_file"
    
    cat > "$env_file" << EOF
# Creative Energy App Server Configuration
# Generated by setup_postgresql_dbaas.sh on $(date)
# Target: DBaaS PostgreSQL Database

# =====================================
# DBaaS Database Configuration
# =====================================
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_SSL=false

# =====================================
# Database Connection Pool Settings
# =====================================
DB_POOL_MIN=2
DB_POOL_MAX=10
DB_POOL_IDLE_TIMEOUT=30000
DB_POOL_CONNECTION_TIMEOUT=5000

# =====================================
# Server Configuration
# =====================================
PORT=$APP_SERVER_PORT
NODE_ENV=production
BIND_HOST=0.0.0.0

# =====================================
# CORS Configuration
# =====================================
ALLOWED_ORIGINS=http://www.your_private_domain_name.net,https://www.your_private_domain_name.net,http://www.your_public_domain_name.net,https://www.your_public_domain_name.net

# =====================================
# Security Configuration
# =====================================
JWT_SECRET=creative_energy_jwt_secret_$(date +%s)_dbaas_db

# =====================================
# Logging Configuration
# =====================================
LOG_LEVEL=info

# =====================================
# Additional Settings
# =====================================
API_TIMEOUT=60000
SESSION_TIMEOUT=1800000
MAX_FILE_SIZE=10485760
EOF
    
    print_success "Environment file created: $env_file"
    print_status "Copy this file to your app-server directory as .env"
}

# Function to run connection tests
run_final_tests() {
    print_step "Step 8: Running final connection and API tests..."
    
    # Test all main API queries that the app will use
    print_status "Testing main API queries..."
    
    # Products list query (for shop.html)
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 'Products API Test' as test_name, COUNT(*) as total_products
        FROM products;
    " >/dev/null 2>&1; then
        print_success "Products API query test passed"
    fi
    
    # Inventory query (for order.html)
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 'Inventory API Test' as test_name, COUNT(*) as total_inventory
        FROM product_inventory_view WHERE stock_quantity > 0;
    " >/dev/null 2>&1; then
        print_success "Inventory API query test passed"
    fi
    
    # Order simulation test (without actually creating an order)
    local test_product_id=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "
        SELECT id FROM products LIMIT 1;
    " 2>/dev/null || echo "1")
    
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 'Order System Test' as test_name, 
               title, 
               stock_quantity 
        FROM product_inventory_view 
        WHERE id = $test_product_id;
    " >/dev/null 2>&1; then
        print_success "Order system query test passed"
    fi
}

# Function to display final setup information
show_setup_completion() {
    echo
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN} 🎉 Creative Energy DBaaS Database Setup Complete! 🎉${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo
    echo -e "${BLUE}📋 Database Configuration:${NC}"
    echo "   Server: $DB_HOST:$DB_PORT"
    echo "   Database: $DB_NAME"
    echo "   Username: $DB_USER"
    echo "   Schema: Creative Energy (products, inventory, orders)"
    echo
    echo -e "${BLUE}🔧 App Server Configuration:${NC}"
    echo "   Generated: .env.app_server"
    echo "   Target: $APP_SERVER_HOST:$APP_SERVER_PORT"
    echo "   API Endpoints: /api/orders/products, /api/orders/create"
    echo
    echo -e "${BLUE}📊 Installation Summary:${NC}"
    local summary_info=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "
        SELECT 
            (SELECT COUNT(*) FROM products) || ' products, ' ||
            (SELECT COUNT(*) FROM inventory) || ' inventory records, ' ||
            (SELECT COUNT(*) FROM orders) || ' orders'
    " 2>/dev/null || echo "Data verification failed")
    echo "   Data: $summary_info"
    echo
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo "   1. Copy .env.app_server to your app-server directory:"
    echo "      scp .env.app_server user@app.your_private_domain_name.net:/path/to/app-server/.env"
    echo
    echo "   2. Install app-server dependencies:"
    echo "      cd /path/to/app-server && npm install"
    echo
    echo "   3. Start the app server:"
    echo "      npm start"
    echo
    echo "   4. Test the connection from app-server:"
    echo "      curl http://app.your_private_domain_name.net:3000/api/orders/products"
    echo
    echo -e "${BLUE}🔍 Verification Commands:${NC}"
    echo "   Database connection:"
    echo "   psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"
    echo
    echo "   View products:"
    echo "   SELECT * FROM product_inventory_view LIMIT 5;"
    echo
    echo "   Monitor app server:"
    echo "   curl http://app.your_private_domain_name.net:3000/health"
    echo
    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo "   • Database credentials are stored in .env.app_server"
    echo "   • Backup your .env file securely"
    echo "   • Monitor database connections and performance"
    echo "   • Daily inventory reset is scheduled via cron on app-server"
    echo
    echo -e "${GREEN}Setup completed successfully! 🎯${NC}"
}

# Function for cleanup on error
cleanup() {
    if [ $? -ne 0 ]; then
        echo
        print_error "Setup failed! Please check the error messages above."
        print_error "Common issues:"
        print_error "1. Database server not accessible"
        print_error "2. Incorrect credentials"
        print_error "3. Firewall blocking connection"
        print_error "4. PostgreSQL not configured for remote connections"
        echo
        print_status "For troubleshooting, verify:"
        print_status "• Database server: systemctl status postgresql-16"
        print_status "• Network: telnet $DB_HOST $DB_PORT"
        print_status "• Credentials: correct username and password"
        print_status "• Firewall: firewall-cmd --list-ports | grep $DB_PORT"
    fi
}

# Main execution function
main() {
    # Show initial information
    echo -e "${CYAN}Starting Creative Energy DBaaS database setup...${NC}"
    echo "Execution time: $(date)"
    echo "Script location: $(pwd)"
    echo
    
    # Execute setup steps
    check_prerequisites
    test_connection
    check_existing_schema
    install_schema
    verify_installation
    test_application_operations
    create_app_env_file
    run_final_tests
    
    # Show completion information
    show_setup_completion
}

# Set trap for cleanup
trap cleanup EXIT

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Run main function with all arguments
    main "$@"
fi