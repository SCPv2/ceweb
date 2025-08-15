#!/bin/bash

# PostgreSQL 16.8 Installation Script for Rocky Linux 9.4
# Creative Energy Database Server Setup
# Server: db.cesvc.net
#
# Usage:
#   sudo bash install_postgresql_vm.sh           # Interactive mode (prompts for passwords)
#   sudo bash install_postgresql_vm.sh --auto    # Automatic mode (uses default passwords)
#   sudo bash install_postgresql_vm.sh -a        # Same as --auto
#
# Default passwords (automatic mode):
#   postgres superuser: ceadmin123!
#   ceadmin user: ceadmin123!

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
DB_NAME="cedb"
DB_USER="ceadmin"
POSTGRES_PASSWORD=""
APP_USER_PASSWORD=""
BACKUP_DIR="/var/backups/postgresql"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} PostgreSQL 16.8 Installation Script${NC}"
echo -e "${BLUE} Creative Energy Database Server${NC}"
echo -e "${BLUE}========================================${NC}"

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

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run this script as root or with sudo"
        exit 1
    fi
}

# Function to set default passwords
set_default_passwords() {
    echo -e "${BLUE}Password Configuration${NC}"
    echo -e "Using default passwords for automatic installation:"
    echo -e "- postgres superuser: ceadmin123!"
    echo -e "- $DB_USER user: ceadmin123!"
    echo
    
    # Set default passwords
    POSTGRES_PASSWORD="ceadmin123!"
    APP_USER_PASSWORD="ceadmin123!"
    
    print_status "Default passwords configured"
    echo
}

# Function to update system
update_system() {
    print_status "Updating system packages..."
    dnf update -y
    dnf install -y wget curl vim git net-tools
}

# Function to install PostgreSQL repository
install_pg_repo() {
    print_status "Installing PostgreSQL 16 repository..."
    dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    
    # Verify repository installation
    if dnf repolist | grep -q pgdg; then
        print_status "PostgreSQL repository installed successfully"
    else
        print_error "Failed to install PostgreSQL repository"
        exit 1
    fi
}

# Function to install PostgreSQL
install_postgresql() {
    print_status "Installing PostgreSQL 16..."
    dnf install -y postgresql16-server postgresql16 postgresql16-contrib
    
    # Verify installation
    if /usr/pgsql-16/bin/postgres --version | grep -q "16"; then
        print_status "PostgreSQL 16 installed successfully"
    else
        print_error "PostgreSQL installation failed"
        exit 1
    fi
}

# Function to initialize database
initialize_database() {
    print_status "Initializing PostgreSQL database..."
    /usr/pgsql-16/bin/postgresql-16-setup initdb
    
    # Start and enable PostgreSQL service
    systemctl start postgresql-16
    systemctl enable postgresql-16
    
    # Check service status
    if systemctl is-active --quiet postgresql-16; then
        print_status "PostgreSQL service started successfully"
    else
        print_error "Failed to start PostgreSQL service"
        exit 1
    fi
}

# Function to configure PostgreSQL
configure_postgresql() {
    print_status "Configuring PostgreSQL..."
    
    # Backup original configuration files
    cp /var/lib/pgsql/16/data/postgresql.conf /var/lib/pgsql/16/data/postgresql.conf.backup
    cp /var/lib/pgsql/16/data/pg_hba.conf /var/lib/pgsql/16/data/pg_hba.conf.backup
    
    # Configure postgresql.conf
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/pgsql/16/data/postgresql.conf
    sed -i "s/#port = 5432/port = 2866/" /var/lib/pgsql/16/data/postgresql.conf
    sed -i "s/#max_connections = 100/max_connections = 100/" /var/lib/pgsql/16/data/postgresql.conf
    sed -i "s/#shared_buffers = 128MB/shared_buffers = 128MB/" /var/lib/pgsql/16/data/postgresql.conf
    
    # Configure pg_hba.conf for remote connections
    echo "# Remote connections" >> /var/lib/pgsql/16/data/pg_hba.conf
    echo "host    all             all             0.0.0.0/0               md5" >> /var/lib/pgsql/16/data/pg_hba.conf
    echo "host    all             all             ::/0                    md5" >> /var/lib/pgsql/16/data/pg_hba.conf
    
    print_status "PostgreSQL configuration updated"
    
    # Restart PostgreSQL to apply new configuration
    print_status "Restarting PostgreSQL to apply configuration changes..."
    systemctl restart postgresql-16
    sleep 5
    
    # Verify PostgreSQL is running on correct port
    if netstat -tlnp | grep ":2866" >/dev/null 2>&1; then
        print_status "PostgreSQL is now running on port 2866"
    else
        print_error "PostgreSQL is not running on port 2866. Please check configuration."
        print_error "Current listening ports:"
        netstat -tlnp | grep postgres || true
        exit 1
    fi
}

# Function to configure firewall
#configure_firewall() {
#    print_status "Configuring firewall..."
    
    # Check if firewalld is running
#    if systemctl is-active --quiet firewalld; then
#        firewall-cmd --permanent --add-port=2866/tcp
#        firewall-cmd --reload
#        print_status "Firewall configured to allow PostgreSQL connections"
#    else
#        print_warning "Firewalld is not running. Please configure firewall manually if needed."
#    fi
#}

# Function to set up database users and database
setup_database() {
    print_status "Setting up database users and database..."
    
    # Set postgres user password using local socket connection (before port change)
    print_status "Setting postgres user password..."
    sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$POSTGRES_PASSWORD';"
    
    # Create application user using socket connection
    print_status "Creating application user..."
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$APP_USER_PASSWORD';"
    sudo -u postgres psql -c "ALTER USER $DB_USER CREATEDB;"
    
    # Create database using socket connection
    print_status "Creating database..."
    sudo -u postgres createdb -O $DB_USER $DB_NAME
    
    print_status "Database and users created successfully"
}

# Function to install schema
install_schema() {
    print_status "Installing database schema..."
    
    # Check if schema file exists
    SCHEMA_FILE="./postgresql_vm_init_schema.sql"
    if [ ! -f "$SCHEMA_FILE" ]; then
        print_error "Schema file $SCHEMA_FILE not found!"
        print_error "Please ensure postgresql_vm_init_schema.sql is in the current directory"
        exit 1
    fi
    
    # Install schema
    sudo -u postgres PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 2866 -d $DB_NAME -f $SCHEMA_FILE
    
    # Grant all privileges to application user
    print_status "Setting up database permissions..."
    sudo -u postgres PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 2866 -d $DB_NAME -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;"
    sudo -u postgres PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 2866 -d $DB_NAME -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;"
    sudo -u postgres PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 2866 -d $DB_NAME -c "GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO $DB_USER;"
    sudo -u postgres PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 2866 -d $DB_NAME -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;"
    sudo -u postgres PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 2866 -d $DB_NAME -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;"
    sudo -u postgres PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 2866 -d $DB_NAME -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO $DB_USER;"
    
    print_status "Database schema installed successfully"
}

# Function to create backup directory and script
setup_backup() {
    print_status "Setting up backup system..."
    
    # Create backup directory
    mkdir -p $BACKUP_DIR
    chown postgres:postgres $BACKUP_DIR
    
    # Create backup script
    cat > /usr/local/bin/backup_creative_energy.sh << 'EOL'
#!/bin/bash
BACKUP_DIR="/var/backups/postgresql"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

# Database backup
sudo -u postgres pg_dump creative_energy > $BACKUP_DIR/creative_energy_$DATE.sql

# Keep only last 7 days of backups
find $BACKUP_DIR -name "creative_energy_*.sql" -mtime +7 -delete

echo "Backup completed: creative_energy_$DATE.sql"
EOL
    
    chmod +x /usr/local/bin/backup_creative_energy.sh
    
    print_status "Backup system configured"
}

# Function to test installation
test_installation() {
    print_status "Testing installation..."
    
    # PostgreSQL was already restarted in configure_postgresql function
    print_status "Verifying PostgreSQL is running on port 2866..."
    sleep 2
    
    # Test database connection and data
    if sudo -u postgres PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 2866 -d $DB_NAME -c "SELECT COUNT(*) FROM products;" >/dev/null 2>&1; then
        print_status "Database connection test passed"
        
        # Show sample data
        echo -e "${BLUE}Sample data verification:${NC}"
        sudo -u postgres PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 2866 -d $DB_NAME -c "SELECT id, title, category FROM products LIMIT 3;"
    else
        print_error "Database connection test failed"
        exit 1
    fi
}

# Function to display final information
display_final_info() {
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} Installation Completed Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${BLUE}Database Information:${NC}"
    echo "  Host: db.cesvc.net ($(hostname -I | awk '{print $1}'))"
    echo "  Port: 2866"
    echo "  Database: $DB_NAME"
    echo "  Application User: $DB_USER"
    echo "  Superuser: postgres"
    echo
    echo -e "${BLUE}Service Status:${NC}"
    systemctl status postgresql-16 --no-pager -l
    echo
    echo -e "${BLUE}Connection Examples:${NC}"
    echo "  Local: sudo -u postgres psql -p 2866 -d $DB_NAME"
    echo "  Remote: psql -h db.cesvc.net -p 2866 -U $DB_USER -d $DB_NAME"
    echo
    echo -e "${BLUE}Backup:${NC}"
    echo "  Manual backup: /usr/local/bin/backup_creative_energy.sh"
    echo "  Backup location: $BACKUP_DIR"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Configure automatic backups with cron if needed"
    echo "2. Update application server connection string"
    echo "3. Test remote connections from application server"
    echo "4. Consider setting up SSL certificates for production"
    echo
}

# Main execution
main() {
    check_root
    set_default_passwords
    
    print_status "Starting PostgreSQL 16.8 installation..."
    
    update_system
    install_pg_repo
    install_postgresql
    initialize_database
    setup_database
    configure_postgresql
#    configure_firewall
    install_schema
    setup_backup
    test_installation
    
    display_final_info
}

# Run main function
main "$@"
