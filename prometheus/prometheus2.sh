#!/bin/bash

#===============================================================================
#
#          FILE: install_prometheus.sh
#
#         USAGE: sudo ./install_prometheus.sh
#
#   DESCRIPTION: Automated installation script for Prometheus monitoring system
#                on Amazon Linux 2 / RHEL-based systems with EC2 service discovery
#
#        AUTHOR: Infrastructure Team
#       VERSION: 1.0.1
#       CREATED: 2025
#
#  REQUIREMENTS: - Root/sudo access
#                - Internet connectivity
#                - wget, tar utilities
#                - IAM role for EC2 service discovery (if using ec2_sd_configs)
#
#         NOTES: This script is idempotent - safe to run multiple times
#
#===============================================================================

#-------------------------------------------------------------------------------
# BASH STRICT MODE
#-------------------------------------------------------------------------------
# -e          : Exit immediately if any command returns non-zero exit status
# -o pipefail : Return value of pipeline is status of last command to exit non-zero
#-------------------------------------------------------------------------------
set -e
set -o pipefail

#-------------------------------------------------------------------------------
# CONFIGURATION VARIABLES
#-------------------------------------------------------------------------------
# Modify these variables according to your environment
# These are defined at the top for easy customization without editing the script
#-------------------------------------------------------------------------------

# Prometheus version to install
# Check latest: https://github.com/prometheus/prometheus/releases
PROMETHEUS_VERSION="3.5.0"

# System user and group for running Prometheus
# Using dedicated user improves security (principle of least privilege)
PROMETHEUS_USER="prometheus"
PROMETHEUS_GROUP="prometheus"

# Directory paths
INSTALL_DIR="/opt/prometheus"           # Temporary download/extraction location
CONFIG_DIR="/etc/prometheus"            # Configuration files location
DATA_DIR="/var/lib/prometheus"          # Time-series database storage
BIN_DIR="/usr/local/bin"                # Binary installation location
LOG_DIR="/var/log/prometheus"           # Log files directory

# Download URL (constructed from version)
DOWNLOAD_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

# AWS Configuration for EC2 Service Discovery
# These settings allow Prometheus to automatically discover EC2 instances
AWS_REGION="ap-south-1"                 # AWS region where instances are located
IAM_ROLE_ARN="arn:aws:iam::638845738277:role/ROLE-IIFL-FINALYZER-PROM-GRAFANA-MONITOR"
AWS_ACCOUNT_TAG="finalyzer-360one"      # Tag value to filter instances

# Data retention settings
# How long to keep metrics data before automatic deletion
RETENTION_DAYS="30d"                    # 30 days retention

# Prometheus web interface settings
PROMETHEUS_PORT="9090"                  # Web UI and API port

# Exporter ports (for scraping targets)
NODE_EXPORTER_PORT="9100"               # Node Exporter (system metrics)
JMX_EXPORTER_PORT="1098"                # JMX Exporter (Java metrics)
MYSQL_EXPORTER_PORT="9104"              # MySQL Exporter (database metrics)

# Scrape intervals
SCRAPE_INTERVAL="15s"                   # How often to scrape targets
EVALUATION_INTERVAL="15s"               # How often to evaluate alerting rules
SCRAPE_TIMEOUT="10s"                    # Timeout for scrape requests

# EC2 service discovery refresh interval
EC2_REFRESH_INTERVAL="5m"

#-------------------------------------------------------------------------------
# COLOR CODES FOR OUTPUT
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color - resets to default

#-------------------------------------------------------------------------------
# LOGGING FUNCTIONS
#-------------------------------------------------------------------------------

# Print informational messages (blue)
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Print success messages (green)
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Print warning messages (yellow)
log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Print error messages (red)
log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Print section headers (cyan)
log_section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

#-------------------------------------------------------------------------------
# HELPER FUNCTIONS
#-------------------------------------------------------------------------------

#
# Function: check_root
# Description: Verify the script is running with root privileges
# Why needed: Installing system services requires root
#
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        log_info "Usage: sudo $0"
        exit 1
    fi
    log_success "Running with root privileges"
}

#
# Function: command_exists
# Description: Check if a command is available in PATH
# Arguments: $1 - command name to check
# Returns: 0 if exists, 1 if not
#
command_exists() {
    command -v "$1" &> /dev/null
}

#
# Function: check_dependencies
# Description: Verify all required tools are installed
#
check_dependencies() {
    log_info "Checking required dependencies..."
    
    local missing_deps=()
    local required_cmds=("wget" "tar" "systemctl")
    
    for cmd in "${required_cmds[@]}"; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        if command_exists yum; then
            log_info "Try: sudo yum install ${missing_deps[*]}"
        elif command_exists apt-get; then
            log_info "Try: sudo apt-get install ${missing_deps[*]}"
        fi
        exit 1
    fi
    
    log_success "All dependencies are available"
}

#
# Function: check_existing_installation
# Description: Detect if Prometheus is already installed
#
check_existing_installation() {
    log_info "Checking for existing Prometheus installation..."
    
    if command_exists prometheus; then
        local current_version
        current_version=$(prometheus --version 2>&1 | head -1 | awk '{print $3}')
        
        log_warn "Prometheus is already installed (version: ${current_version})"
        read -p "Do you want to proceed with installation/upgrade? (y/n): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled by user"
            exit 0
        fi
        
        log_info "Stopping existing Prometheus service..."
        systemctl stop prometheus 2>/dev/null || true
        systemctl disable prometheus 2>/dev/null || true
    else
        log_success "No existing Prometheus installation found"
    fi
}

#
# Function: cleanup_on_error
# Description: Clean up temporary files if installation fails
#
cleanup_on_error() {
    log_error "Installation failed! Performing cleanup..."
    rm -f "${INSTALL_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" 2>/dev/null
    rm -rf "${INSTALL_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64" 2>/dev/null
    log_info "Cleanup completed. Please check the error messages above."
    exit 1
}

#
# Function: cleanup_installation_files
# Description: Remove temporary files after successful installation
#
cleanup_installation_files() {
    log_info "Cleaning up installation files..."
    rm -f "${INSTALL_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    rm -rf "${INSTALL_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64"
    log_success "Installation files cleaned up"
}

#-------------------------------------------------------------------------------
# INSTALLATION FUNCTIONS
#-------------------------------------------------------------------------------

#
# Function: create_user_and_group
# Description: Create dedicated system user and group for Prometheus
# Why needed: Security best practice - run services with minimal privileges
#
create_user_and_group() {
    log_section "Creating Prometheus User and Group"
    
    # Check if group already exists
    if getent group "${PROMETHEUS_GROUP}" &>/dev/null; then
        log_warn "Group '${PROMETHEUS_GROUP}' already exists"
    else
        groupadd --system "${PROMETHEUS_GROUP}"
        log_success "Created group: ${PROMETHEUS_GROUP}"
    fi
    
    # Check if user already exists
    if id "${PROMETHEUS_USER}" &>/dev/null; then
        log_warn "User '${PROMETHEUS_USER}' already exists"
    else
        # Create system user with:
        # --system        : Create a system account
        # --no-create-home: Don't create home directory
        # --shell         : Prevent interactive login with /bin/false
        # --gid           : Assign to prometheus group
        useradd --system \
                --no-create-home \
                --shell /bin/false \
                --gid "${PROMETHEUS_GROUP}" \
                "${PROMETHEUS_USER}"
        log_success "Created user: ${PROMETHEUS_USER}"
    fi
}

#
# Function: create_directories
# Description: Create all required directories for Prometheus
# Why: -p flag creates parent directories and doesn't error if exists (idempotent)
#
create_directories() {
    log_section "Creating Directory Structure"
    
    local directories=(
        "${INSTALL_DIR}"                    # Temporary installation files
        "${CONFIG_DIR}"                     # Main configuration directory
        "${CONFIG_DIR}/consoles"            # Console templates
        "${CONFIG_DIR}/console_libraries"   # Console template libraries
        "${CONFIG_DIR}/rules"               # Alerting/recording rules
        "${CONFIG_DIR}/targets"             # File-based service discovery
        "${DATA_DIR}"                       # TSDB data storage
        "${LOG_DIR}"                        # Log files
    )
    
    for dir in "${directories[@]}"; do
        if [[ -d "$dir" ]]; then
            log_warn "Directory already exists: $dir"
        else
            mkdir -p "$dir"
            log_success "Created directory: $dir"
        fi
    done
}

#
# Function: download_prometheus
# Description: Download Prometheus tarball from GitHub releases
#
download_prometheus() {
    log_section "Downloading Prometheus ${PROMETHEUS_VERSION}"
    
    local tarball="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    local tarball_path="${INSTALL_DIR}/${tarball}"
    
    cd "${INSTALL_DIR}"
    
    # Remove existing tarball if present
    if [[ -f "${tarball_path}" ]]; then
        log_warn "Tarball already exists, removing old file..."
        rm -f "${tarball_path}"
    fi
    
    log_info "Downloading from: ${DOWNLOAD_URL}"
    
    # Download with progress indicator
    if wget -q --show-progress "${DOWNLOAD_URL}" -O "${tarball_path}"; then
        log_success "Download completed successfully"
    else
        log_error "Failed to download Prometheus"
        exit 1
    fi
    
    # Verify download
    if [[ ! -s "${tarball_path}" ]]; then
        log_error "Downloaded file is empty or missing"
        exit 1
    fi
    
    log_info "Downloaded file size: $(du -h "${tarball_path}" | cut -f1)"
}

#
# Function: extract_prometheus
# Description: Extract the downloaded tarball
# Flags: -x (extract), -z (gzip), -f (file)
#
extract_prometheus() {
    log_section "Extracting Prometheus"
    
    local tarball="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    local tarball_path="${INSTALL_DIR}/${tarball}"
    local extracted_dir="${INSTALL_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64"
    
    cd "${INSTALL_DIR}"
    
    # Remove old extraction if exists
    if [[ -d "${extracted_dir}" ]]; then
        log_warn "Removing existing extracted directory..."
        rm -rf "${extracted_dir}"
    fi
    
    log_info "Extracting archive..."
    
    if tar -xzf "${tarball_path}"; then
        log_success "Extraction completed"
    else
        log_error "Failed to extract tarball"
        exit 1
    fi
    
    # Verify extraction
    if [[ ! -d "${extracted_dir}" ]]; then
        log_error "Extracted directory not found"
        exit 1
    fi
    
    log_info "Extracted contents:"
    ls -la "${extracted_dir}"
}

#
# Function: install_binaries
# Description: Copy Prometheus binaries to system location
#
install_binaries() {
    log_section "Installing Binaries"
    
    local extracted_dir="${INSTALL_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64"
    
    # Copy main prometheus binary
    log_info "Installing prometheus binary..."
    cp "${extracted_dir}/prometheus" "${BIN_DIR}/"
    
    # Copy promtool binary (for config validation and querying)
    log_info "Installing promtool binary..."
    cp "${extracted_dir}/promtool" "${BIN_DIR}/"
    
    # Set ownership to prometheus user
    chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${BIN_DIR}/prometheus"
    chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${BIN_DIR}/promtool"
    
    # Set executable permissions (755 = rwxr-xr-x)
    chmod 755 "${BIN_DIR}/prometheus"
    chmod 755 "${BIN_DIR}/promtool"
    
    log_success "Binaries installed to ${BIN_DIR}/"
    
    # Copy console templates
    log_info "Installing console templates..."
    if [[ -d "${extracted_dir}/consoles" ]]; then
        cp -r "${extracted_dir}/consoles/"* "${CONFIG_DIR}/consoles/" 2>/dev/null || true
    fi
    
    if [[ -d "${extracted_dir}/console_libraries" ]]; then
        cp -r "${extracted_dir}/console_libraries/"* "${CONFIG_DIR}/console_libraries/" 2>/dev/null || true
    fi
    
    log_success "Console templates installed"
    
    # Verify installation
    log_info "Verifying binary installation..."
    if "${BIN_DIR}/prometheus" --version &>/dev/null; then
        log_success "prometheus binary is functional"
    else
        log_error "prometheus binary verification failed"
        exit 1
    fi
    
    if "${BIN_DIR}/promtool" --version &>/dev/null; then
        log_success "promtool binary is functional"
    else
        log_error "promtool binary verification failed"
        exit 1
    fi
}

#
# Function: create_configuration
# Description: Generate the main Prometheus configuration file
#
# Configuration sections:
# - global: Default settings for all scrape configs
# - alerting: Alertmanager connection settings
# - rule_files: Paths to alerting/recording rules
# - scrape_configs: Define what to monitor and how
#
create_configuration() {
    log_section "Creating Configuration File"
    
    log_info "Generating prometheus.yml..."
    
    cat > "${CONFIG_DIR}/prometheus.yml" <<EOF
#===============================================================================
# Prometheus Configuration File
#===============================================================================
# Auto-generated by: install_prometheus.sh
# Generated on:      $(date '+%Y-%m-%d %H:%M:%S')
# Prometheus Version: ${PROMETHEUS_VERSION}
#
# Documentation: https://prometheus.io/docs/prometheus/latest/configuration/
#===============================================================================

#-------------------------------------------------------------------------------
# GLOBAL CONFIGURATION
#-------------------------------------------------------------------------------
global:
  # scrape_interval: How frequently to scrape targets
  scrape_interval: ${SCRAPE_INTERVAL}
  
  # evaluation_interval: How frequently to evaluate rules
  evaluation_interval: ${EVALUATION_INTERVAL}
  
  # scrape_timeout: Per-scrape timeout
  scrape_timeout: ${SCRAPE_TIMEOUT}
  
  # external_labels: Added to metrics when communicating with external systems
  external_labels:
    monitor: 'prometheus-server'
    environment: 'production'
    region: '${AWS_REGION}'

#-------------------------------------------------------------------------------
# ALERTMANAGER CONFIGURATION
#-------------------------------------------------------------------------------
alerting:
  alertmanagers:
    - static_configs:
        - targets: []
          # Uncomment when Alertmanager is deployed:
          # - targets: ['localhost:9093']

#-------------------------------------------------------------------------------
# RULE FILES
#-------------------------------------------------------------------------------
rule_files:
  # - '${CONFIG_DIR}/rules/recording_rules.yml'
  # - '${CONFIG_DIR}/rules/alerting_rules.yml'

#-------------------------------------------------------------------------------
# SCRAPE CONFIGURATIONS
#-------------------------------------------------------------------------------
scrape_configs:

  #=============================================================================
  # JOB: Prometheus Self-Monitoring
  #=============================================================================
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:${PROMETHEUS_PORT}']
        labels:
          instance_name: 'prometheus-server'
          service: 'prometheus'

  #=============================================================================
  # JOB: Local Node Exporter (Monitoring Server)
  #=============================================================================
  - job_name: 'monitoring_server_node'
    static_configs:
      - targets: ['localhost:${NODE_EXPORTER_PORT}']
        labels:
          instance_name: 'monitoring-server'
          service: 'node_exporter'
          environment: 'production'

  #=============================================================================
  # JOB: Node Exporter - EC2 Service Discovery
  #=============================================================================
  # Discovers EC2 instances with Prometheus_jmx=true OR Prometheus_mysql=true
  #-----------------------------------------------------------------------------
  - job_name: 'node_exporter'
    
    ec2_sd_configs:
      - region: '${AWS_REGION}'
        role_arn: '${IAM_ROLE_ARN}'
        port: ${NODE_EXPORTER_PORT}
        refresh_interval: ${EC2_REFRESH_INTERVAL}
        
        # EC2 API filters - efficient pre-filtering
        filters:
          - name: 'tag:AWS_Account'
            values: ['${AWS_ACCOUNT_TAG}']
          - name: 'instance-state-name'
            values: ['running']
    
    relabel_configs:
      # Keep instances with Prometheus_jmx=true OR Prometheus_mysql=true
      - source_labels: [__meta_ec2_tag_Prometheus_jmx, __meta_ec2_tag_Prometheus_mysql]
        separator: ';'
        regex: 'true;.*|.*;true'
        action: keep

      # Set instance_name from EC2 Name tag
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name

      # Set environment label
      - source_labels: [__meta_ec2_tag_Environment]
        target_label: environment

      # Set target address using private IP
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '\${1}:${NODE_EXPORTER_PORT}'

      # Add availability zone label
      - source_labels: [__meta_ec2_availability_zone]
        target_label: availability_zone

      # Add instance type label
      - source_labels: [__meta_ec2_instance_type]
        target_label: instance_type

      # Add instance ID label
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id

      # Add private IP label
      - source_labels: [__meta_ec2_private_ip]
        target_label: private_ip

  #=============================================================================
  # JOB: JMX Exporter - EC2 Service Discovery
  #=============================================================================
  # Discovers EC2 instances with Prometheus_jmx=true
  #-----------------------------------------------------------------------------
  - job_name: 'jmx_exporter'
    
    ec2_sd_configs:
      - region: '${AWS_REGION}'
        role_arn: '${IAM_ROLE_ARN}'
        port: ${JMX_EXPORTER_PORT}
        refresh_interval: ${EC2_REFRESH_INTERVAL}
        
        filters:
          - name: 'tag:AWS_Account'
            values: ['${AWS_ACCOUNT_TAG}']
          - name: 'tag:Prometheus_jmx'
            values: ['true']
          - name: 'instance-state-name'
            values: ['running']
    
    relabel_configs:
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name

      - source_labels: [__meta_ec2_tag_Environment]
        target_label: environment

      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '\${1}:${JMX_EXPORTER_PORT}'

      - source_labels: [__meta_ec2_availability_zone]
        target_label: availability_zone

      - source_labels: [__meta_ec2_instance_type]
        target_label: instance_type

      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id

      - source_labels: [__meta_ec2_private_ip]
        target_label: private_ip

      - target_label: service
        replacement: 'jmx_exporter'

  #=============================================================================
  # JOB: MySQL Exporter - EC2 Service Discovery
  #=============================================================================
  # Discovers EC2 instances with Prometheus_mysql=true
  #-----------------------------------------------------------------------------
  - job_name: 'mysql_exporter'
    
    ec2_sd_configs:
      - region: '${AWS_REGION}'
        role_arn: '${IAM_ROLE_ARN}'
        port: ${MYSQL_EXPORTER_PORT}
        refresh_interval: ${EC2_REFRESH_INTERVAL}
        
        filters:
          - name: 'tag:AWS_Account'
            values: ['${AWS_ACCOUNT_TAG}']
          - name: 'tag:Prometheus_mysql'
            values: ['true']
          - name: 'instance-state-name'
            values: ['running']
    
    relabel_configs:
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name

      - source_labels: [__meta_ec2_tag_Environment]
        target_label: environment

      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '\${1}:${MYSQL_EXPORTER_PORT}'

      - source_labels: [__meta_ec2_availability_zone]
        target_label: availability_zone

      - source_labels: [__meta_ec2_instance_type]
        target_label: instance_type

      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id

      - source_labels: [__meta_ec2_private_ip]
        target_label: private_ip

      - target_label: service
        replacement: 'mysql_exporter'

#===============================================================================
# END OF CONFIGURATION
#===============================================================================
EOF

    log_success "Configuration file created: ${CONFIG_DIR}/prometheus.yml"
}

#
# Function: set_permissions
# Description: Set correct ownership and permissions for all Prometheus files
#
set_permissions() {
    log_section "Setting Permissions"
    
    log_info "Setting ownership for ${CONFIG_DIR}..."
    chown -R "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${CONFIG_DIR}"
    
    log_info "Setting ownership for ${DATA_DIR}..."
    chown -R "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${DATA_DIR}"
    
    log_info "Setting ownership for ${LOG_DIR}..."
    chown -R "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${LOG_DIR}"
    
    # Set directory permissions (755 = rwxr-xr-x)
    chmod 755 "${CONFIG_DIR}"
    chmod 755 "${DATA_DIR}"
    chmod 755 "${LOG_DIR}"
    
    # Set file permissions (644 = rw-r--r--)
    chmod 644 "${CONFIG_DIR}/prometheus.yml"
    
    log_success "Permissions configured successfully"
}

#
# Function: validate_configuration
# Description: Use promtool to validate the configuration file
#
validate_configuration() {
    log_section "Validating Configuration"
    
    log_info "Running promtool configuration check..."
    
    if "${BIN_DIR}/promtool" check config "${CONFIG_DIR}/prometheus.yml"; then
        log_success "Configuration validation PASSED"
    else
        log_error "Configuration validation FAILED"
        exit 1
    fi
}

#
# Function: create_systemd_service
# Description: Create systemd service unit file for Prometheus
#
# Key systemd directives explained in comments below
#
create_systemd_service() {
    log_section "Creating Systemd Service"
    
    log_info "Creating service unit file..."
    
    cat > /etc/systemd/system/prometheus.service <<EOF
#===============================================================================
# Prometheus Systemd Service Unit File
#===============================================================================
# Auto-generated by: install_prometheus.sh
# Generated on:      $(date '+%Y-%m-%d %H:%M:%S')
#===============================================================================

[Unit]
# Description: Human-readable service description
Description=Prometheus Monitoring System and Time Series Database
Documentation=https://prometheus.io/docs/

# Wants: Soft dependency - try to start network first
Wants=network-online.target

# After: Don't start until network is ready
After=network-online.target

[Service]
# User/Group: Run as non-root user for security
User=${PROMETHEUS_USER}
Group=${PROMETHEUS_GROUP}

# Type: simple means process started by ExecStart is the main process
Type=simple

#-------------------------------------------------------------------------------
# Prometheus Startup Command with Arguments
#-------------------------------------------------------------------------------
ExecStart=${BIN_DIR}/prometheus \\
    --config.file=${CONFIG_DIR}/prometheus.yml \\
    --storage.tsdb.path=${DATA_DIR} \\
    --storage.tsdb.retention.time=${RETENTION_DAYS} \\
    --web.console.templates=${CONFIG_DIR}/consoles \\
    --web.console.libraries=${CONFIG_DIR}/console_libraries \\
    --web.listen-address=0.0.0.0:${PROMETHEUS_PORT} \\
    --web.enable-lifecycle \\
    --web.enable-admin-api \\
    --log.level=info \\
    --log.format=logfmt

# ExecReload: Command to reload config (sends SIGHUP)
ExecReload=/bin/kill -HUP \$MAINPID

#-------------------------------------------------------------------------------
# Restart Configuration
#-------------------------------------------------------------------------------
# Restart on failure with 5 second delay
Restart=on-failure
RestartSec=5s

# Limit restart attempts: max 3 in 60 seconds
StartLimitBurst=3
StartLimitIntervalSec=60

#-------------------------------------------------------------------------------
# Resource Limits
#-------------------------------------------------------------------------------
# Max open file descriptors (Prometheus uses many for TSDB)
LimitNOFILE=65536
LimitNPROC=4096

#-------------------------------------------------------------------------------
# Security Hardening
#-------------------------------------------------------------------------------
# NoNewPrivileges: Prevent privilege escalation
NoNewPrivileges=yes

# ProtectSystem: Mount system directories read-only
ProtectSystem=full

# ProtectHome: Make home directories inaccessible
ProtectHome=yes

# PrivateTmp: Use private /tmp
PrivateTmp=yes

# ReadWritePaths: Allow writes only to these paths
ReadWritePaths=${DATA_DIR} ${LOG_DIR}

#-------------------------------------------------------------------------------
# Logging
#-------------------------------------------------------------------------------
StandardOutput=journal
StandardError=journal
SyslogIdentifier=prometheus

[Install]
# WantedBy: Start with multi-user target (normal boot)
WantedBy=multi-user.target
EOF

    chmod 644 /etc/systemd/system/prometheus.service
    
    log_success "Systemd service file created"
    
    log_info "Reloading systemd daemon..."
    systemctl daemon-reload
    
    log_success "Systemd daemon reloaded"
}

#
# Function: start_service
# Description: Enable and start the Prometheus service
#
start_service() {
    log_section "Starting Prometheus Service"
    
    log_info "Enabling Prometheus service for auto-start..."
    systemctl enable prometheus
    
    log_info "Starting Prometheus service..."
    systemctl start prometheus
    
    log_info "Waiting for service to initialize..."
    sleep 5
    
    if systemctl is-active --quiet prometheus; then
        log_success "Prometheus service is running"
    else
        log_error "Prometheus service failed to start"
        journalctl -u prometheus --no-pager -n 30
        exit 1
    fi
}

#
# Function: configure_firewall
# Description: Configure firewall to allow Prometheus port
#
configure_firewall() {
    log_section "Configuring Firewall"
    
    if systemctl is-active --quiet firewalld; then
        log_info "Firewalld is active, adding Prometheus port..."
        firewall-cmd --permanent --add-port=${PROMETHEUS_PORT}/tcp
        firewall-cmd --reload
        log_success "Firewall configured - port ${PROMETHEUS_PORT}/tcp opened"
    elif command_exists ufw && ufw status 2>/dev/null | grep -q "active"; then
        log_info "UFW is active, adding Prometheus port..."
        ufw allow ${PROMETHEUS_PORT}/tcp
        log_success "UFW configured - port ${PROMETHEUS_PORT}/tcp opened"
    else
        log_warn "No active firewall detected, skipping configuration"
        log_info "Ensure port ${PROMETHEUS_PORT} is accessible if needed"
    fi
}

#
# Function: print_summary
# Description: Display installation summary and useful commands
#
print_summary() {
    # Get version info - use || true to prevent pipefail issues
    local installed_version
    installed_version=$("${BIN_DIR}/prometheus" --version 2>&1 | head -1) || true
    
    # Get server IP - use || true to handle errors gracefully
    local server_ip
    server_ip=$(hostname -I 2>/dev/null | awk '{print $1}') || server_ip="<server-ip>"
    
    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}       PROMETHEUS INSTALLATION COMPLETED SUCCESSFULLY${NC}"
    echo "==============================================================================="
    echo ""
    echo "  Installation Details:"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    echo "  Version:            ${PROMETHEUS_VERSION}"
    echo "  Binary Location:    ${BIN_DIR}/prometheus"
    echo "  Config File:        ${CONFIG_DIR}/prometheus.yml"
    echo "  Data Directory:     ${DATA_DIR}"
    echo "  Service Name:       prometheus"
    echo "  Running As:         ${PROMETHEUS_USER}:${PROMETHEUS_GROUP}"
    echo "  Retention Period:   ${RETENTION_DAYS}"
    echo ""
    echo "  Access URLs:"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    echo "  Web UI:             http://${server_ip}:${PROMETHEUS_PORT}"
    echo "  Targets:            http://${server_ip}:${PROMETHEUS_PORT}/targets"
    echo "  Configuration:      http://${server_ip}:${PROMETHEUS_PORT}/config"
    echo "  Metrics:            http://${server_ip}:${PROMETHEUS_PORT}/metrics"
    echo "  Health Check:       http://${server_ip}:${PROMETHEUS_PORT}/-/healthy"
    echo ""
    echo "  Useful Commands:"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    echo "  Check version:      prometheus --version"
    echo "  Service status:     sudo systemctl status prometheus"
    echo "  View logs:          sudo journalctl -u prometheus -f"
    echo "  Restart service:    sudo systemctl restart prometheus"
    echo "  Stop service:       sudo systemctl stop prometheus"
    echo "  Validate config:    promtool check config ${CONFIG_DIR}/prometheus.yml"
    echo "  Reload config:      curl -X POST http://localhost:${PROMETHEUS_PORT}/-/reload"
    echo ""
    echo "  Scrape Jobs Configured:"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    echo "  • prometheus          - Self-monitoring (localhost:${PROMETHEUS_PORT})"
    echo "  • monitoring_server   - Local node exporter (localhost:${NODE_EXPORTER_PORT})"
    echo "  • node_exporter       - EC2 discovery (port ${NODE_EXPORTER_PORT})"
    echo "  • jmx_exporter        - Java apps EC2 discovery (port ${JMX_EXPORTER_PORT})"
    echo "  • mysql_exporter      - MySQL EC2 discovery (port ${MYSQL_EXPORTER_PORT})"
    echo ""
    echo "  Required EC2 Tags for Discovery:"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    echo "  • AWS_Account:        ${AWS_ACCOUNT_TAG}"
    echo "  • Prometheus_jmx:     true  (for JMX monitoring)"
    echo "  • Prometheus_mysql:   true  (for MySQL monitoring)"
    echo "  • Name:               <instance name>"
    echo "  • Environment:        <environment name>"
    echo ""
    echo "==============================================================================="
    echo ""
}

#
# Function: final_verification
# Description: Display final verification info
# Note: This runs after trap is disabled to prevent false errors
#
final_verification() {
    log_section "Final Verification"
    echo ""
    echo "Prometheus Version:"
    # Use subshell and || true to prevent SIGPIPE errors with pipefail
    ("${BIN_DIR}/prometheus" --version 2>&1 || true) | head -3
    echo ""
    echo "Service Status:"
    # Store output in variable first to avoid pipe issues
    local status_output
    status_output=$(systemctl status prometheus --no-pager 2>&1 || true)
    echo "${status_output}" | head -15
    echo ""
}

#-------------------------------------------------------------------------------
# MAIN EXECUTION
#-------------------------------------------------------------------------------

main() {
    log_section "Prometheus ${PROMETHEUS_VERSION} Installation Script"
    
    # Set up error trap for cleanup during critical installation steps
    trap cleanup_on_error ERR
    
    # Pre-installation checks
    check_root
    check_dependencies
    check_existing_installation
    
    # Installation steps
    create_user_and_group
    create_directories
    download_prometheus
    extract_prometheus
    install_binaries
    create_configuration
    set_permissions
    validate_configuration
    create_systemd_service
    start_service
    
    # Post-installation
    cleanup_installation_files
    configure_firewall
    
    #---------------------------------------------------------------------------
    # DISABLE ERROR TRAP FOR NON-CRITICAL SECTION
    #---------------------------------------------------------------------------
    # The summary and verification sections are informational only.
    # We disable the error trap to prevent false failures from commands like
    # 'head' which can cause SIGPIPE errors when used with 'set -o pipefail'
    #---------------------------------------------------------------------------
    trap - ERR
    
    # Show summary (non-critical)
    print_summary
    
    # Final verification (non-critical)
    final_verification
    
    log_success "Installation completed successfully!"
}

# Run main function with all script arguments
main "$@"