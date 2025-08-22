#!/bin/bash

# Master Configuration Loader for Samsung Cloud Platform
# Loads configuration from master_config.json and exports as environment variables
# Usage: source /path/to/load_master_config.sh

MASTER_CONFIG_FILE="/home/rocky/ceweb/web-server/master_config.json"

# Function to log messages
log_config() {
    echo -e "\033[0;34m[CONFIG] $1\033[0m"
}

error_config() {
    echo -e "\033[0;31m[CONFIG ERROR] $1\033[0m"
}

# Check if master_config.json exists
if [ ! -f "$MASTER_CONFIG_FILE" ]; then
    error_config "Master config file not found: $MASTER_CONFIG_FILE"
    error_config "Please ensure the file exists before running installation scripts"
    exit 1
fi

# Check if jq is available for JSON parsing
if ! command -v jq &> /dev/null; then
    log_config "Installing jq for JSON parsing..."
    if command -v dnf &> /dev/null; then
        dnf install -y jq
    elif command -v yum &> /dev/null; then
        yum install -y jq
    elif command -v apt &> /dev/null; then
        apt update && apt install -y jq
    else
        error_config "Could not install jq. Please install it manually."
        exit 1
    fi
fi

log_config "Loading configuration from: $MASTER_CONFIG_FILE"

# Load configuration values using jq
export PUBLIC_DOMAIN_NAME=$(jq -r '.infrastructure.domain.public_domain_name' "$MASTER_CONFIG_FILE")
export PRIVATE_DOMAIN_NAME=$(jq -r '.infrastructure.domain.private_domain_name' "$MASTER_CONFIG_FILE")
export PUBLIC_HOSTED_ZONE_ID=$(jq -r '.infrastructure.domain.public_hosted_zone_id' "$MASTER_CONFIG_FILE")
export PRIVATE_HOSTED_ZONE_ID=$(jq -r '.infrastructure.domain.private_hosted_zone_id' "$MASTER_CONFIG_FILE")

# Network configuration
export VPC_CIDR=$(jq -r '.infrastructure.network.vpc_cidr' "$MASTER_CONFIG_FILE")
export WEB_SUBNET_CIDR=$(jq -r '.infrastructure.network.web_subnet_cidr' "$MASTER_CONFIG_FILE")
export APP_SUBNET_CIDR=$(jq -r '.infrastructure.network.app_subnet_cidr' "$MASTER_CONFIG_FILE")
export DB_SUBNET_CIDR=$(jq -r '.infrastructure.network.db_subnet_cidr' "$MASTER_CONFIG_FILE")

# Load Balancer IPs
export WEB_LB_SERVICE_IP=$(jq -r '.infrastructure.load_balancer.web_lb_service_ip' "$MASTER_CONFIG_FILE")
export APP_LB_SERVICE_IP=$(jq -r '.infrastructure.load_balancer.app_lb_service_ip' "$MASTER_CONFIG_FILE")

# Server IPs
export WEB_PRIMARY_IP=$(jq -r '.infrastructure.servers.web_primary_ip' "$MASTER_CONFIG_FILE")
export WEB_SECONDARY_IP=$(jq -r '.infrastructure.servers.web_secondary_ip' "$MASTER_CONFIG_FILE")
export APP_PRIMARY_IP=$(jq -r '.infrastructure.servers.app_primary_ip' "$MASTER_CONFIG_FILE")
export APP_SECONDARY_IP=$(jq -r '.infrastructure.servers.app_secondary_ip' "$MASTER_CONFIG_FILE")
export DB_PRIMARY_IP=$(jq -r '.infrastructure.servers.db_primary_ip' "$MASTER_CONFIG_FILE")
export BASTION_IP=$(jq -r '.infrastructure.servers.bastion_ip' "$MASTER_CONFIG_FILE")

# Application configuration
export WEB_NGINX_PORT=$(jq -r '.application.web_server.nginx_port' "$MASTER_CONFIG_FILE")
export WEB_SSL_ENABLED=$(jq -r '.application.web_server.ssl_enabled' "$MASTER_CONFIG_FILE")
export WEB_UPSTREAM_TARGET=$(jq -r '.application.web_server.upstream_target' "$MASTER_CONFIG_FILE")
export WEB_FALLBACK_TARGET=$(jq -r '.application.web_server.fallback_target' "$MASTER_CONFIG_FILE")

export APP_PORT=$(jq -r '.application.app_server.port' "$MASTER_CONFIG_FILE")
export APP_NODE_ENV=$(jq -r '.application.app_server.node_env' "$MASTER_CONFIG_FILE")
export APP_DATABASE_HOST=$(jq -r '.application.app_server.database_host' "$MASTER_CONFIG_FILE")
export APP_DATABASE_PORT=$(jq -r '.application.app_server.database_port' "$MASTER_CONFIG_FILE")
export APP_DATABASE_NAME=$(jq -r '.application.app_server.database_name' "$MASTER_CONFIG_FILE")
export APP_SESSION_SECRET=$(jq -r '.application.app_server.session_secret' "$MASTER_CONFIG_FILE")

export DB_TYPE=$(jq -r '.application.database.type' "$MASTER_CONFIG_FILE")
export DB_PORT=$(jq -r '.application.database.port' "$MASTER_CONFIG_FILE")
export DB_MAX_CONNECTIONS=$(jq -r '.application.database.max_connections' "$MASTER_CONFIG_FILE")

# Object Storage configuration
export OBJECT_STORAGE_ACCESS_KEY_ID=$(jq -r '.object_storage.access_key_id' "$MASTER_CONFIG_FILE")
export OBJECT_STORAGE_SECRET_ACCESS_KEY=$(jq -r '.object_storage.secret_access_key' "$MASTER_CONFIG_FILE")
export OBJECT_STORAGE_REGION=$(jq -r '.object_storage.region' "$MASTER_CONFIG_FILE")
export OBJECT_STORAGE_BUCKET_NAME=$(jq -r '.object_storage.bucket_name' "$MASTER_CONFIG_FILE")
export OBJECT_STORAGE_BUCKET_STRING=$(jq -r '.object_storage.bucket_string' "$MASTER_CONFIG_FILE")
export OBJECT_STORAGE_PRIVATE_ENDPOINT=$(jq -r '.object_storage.private_endpoint' "$MASTER_CONFIG_FILE")
export OBJECT_STORAGE_PUBLIC_ENDPOINT=$(jq -r '.object_storage.public_endpoint' "$MASTER_CONFIG_FILE")
export OBJECT_STORAGE_MEDIA_FOLDER=$(jq -r '.object_storage.folders.media' "$MASTER_CONFIG_FILE")
export OBJECT_STORAGE_AUDITION_FOLDER=$(jq -r '.object_storage.folders.audition' "$MASTER_CONFIG_FILE")

# Security configuration
export SECURITY_SSH_KEY_NAME=$(jq -r '.security.firewall.ssh_key_name' "$MASTER_CONFIG_FILE")
export SECURITY_SSL_CERT_PATH=$(jq -r '.security.ssl.certificate_path' "$MASTER_CONFIG_FILE")
export SECURITY_SSL_KEY_PATH=$(jq -r '.security.ssl.private_key_path' "$MASTER_CONFIG_FILE")

# Deployment configuration
export DEPLOYMENT_GIT_REPOSITORY=$(jq -r '.deployment.git_repository' "$MASTER_CONFIG_FILE")
export DEPLOYMENT_GIT_BRANCH=$(jq -r '.deployment.git_branch' "$MASTER_CONFIG_FILE")
export DEPLOYMENT_AUTO_DEPLOYMENT=$(jq -r '.deployment.auto_deployment' "$MASTER_CONFIG_FILE")

# User customization
export USER_COMPANY_NAME=$(jq -r '.user_customization.company_name' "$MASTER_CONFIG_FILE")
export USER_ADMIN_EMAIL=$(jq -r '.user_customization.admin_email' "$MASTER_CONFIG_FILE")
export USER_TIMEZONE=$(jq -r '.user_customization.timezone' "$MASTER_CONFIG_FILE")

# Construct dynamic values based on configuration
export DEFAULT_SERVER_NAMES="www.$PRIVATE_DOMAIN_NAME www.$PUBLIC_DOMAIN_NAME"
export APP_SERVER_HOST="app.$PRIVATE_DOMAIN_NAME"
export DB_SERVER_HOST="db.$PRIVATE_DOMAIN_NAME"

# Object Storage URLs
export OBJECT_STORAGE_MEDIA_BASE="${OBJECT_STORAGE_PUBLIC_ENDPOINT}/${OBJECT_STORAGE_BUCKET_NAME}/${OBJECT_STORAGE_MEDIA_FOLDER}"
export OBJECT_STORAGE_FILES_BASE="${OBJECT_STORAGE_PUBLIC_ENDPOINT}/${OBJECT_STORAGE_BUCKET_NAME}/${OBJECT_STORAGE_AUDITION_FOLDER}"

# Validation
validate_config() {
    local errors=0
    
    if [ "$PUBLIC_DOMAIN_NAME" = "null" ] || [ -z "$PUBLIC_DOMAIN_NAME" ]; then
        error_config "Public domain name is not configured"
        ((errors++))
    fi
    
    if [ "$PRIVATE_DOMAIN_NAME" = "null" ] || [ -z "$PRIVATE_DOMAIN_NAME" ]; then
        error_config "Private domain name is not configured"
        ((errors++))
    fi
    
    if [ "$OBJECT_STORAGE_BUCKET_STRING" = "null" ] || [ -z "$OBJECT_STORAGE_BUCKET_STRING" ]; then
        error_config "Object storage bucket string is not configured"
        ((errors++))
    fi
    
    if [ $errors -gt 0 ]; then
        error_config "Configuration validation failed. Please check your master_config.json"
        return 1
    fi
    
    return 0
}

# Run validation
if validate_config; then
    log_config "Configuration loaded successfully:"
    log_config "  Public Domain: $PUBLIC_DOMAIN_NAME"
    log_config "  Private Domain: $PRIVATE_DOMAIN_NAME" 
    log_config "  Web LB IP: $WEB_LB_SERVICE_IP"
    log_config "  App LB IP: $APP_LB_SERVICE_IP"
    log_config "  Object Storage Bucket: $OBJECT_STORAGE_BUCKET_NAME"
    log_config "  Default Server Names: $DEFAULT_SERVER_NAMES"
    log_config "  App Server Host: $APP_SERVER_HOST"
else
    exit 1
fi