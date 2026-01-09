#!/bin/bash

#===============================================================================
# Prometheus Installation Script for Amazon Linux 2 / RHEL-based Systems
#===============================================================================
# Description: Installs and configures Prometheus with EC2 service discovery
# Author: Infrastructure Team
# Version: 1.0
# Prometheus Version: 3.5.0
#
# Prerequisites:
#   - Root or sudo access
#   - Internet connectivity to download Prometheus
#   - IAM role attached to EC2 for EC2 service discovery (if using ec2_sd_configs)
#
# Usage:
#   chmod +x install_prometheus.sh
#   sudo ./install_prometheus.sh
#===============================================================================

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Catch errors in piped commands

#-------------------------------------------------------------------------------
# CONFIGURATION VARIABLES - Modify these as needed
#-------------------------------------------------------------------------------
PROMETHEUS_VERSION="3.5.0"
PROMETHEUS_USER="prometheus"
PROMETHEUS_GROUP="prometheus"
INSTALL_DIR="/opt/prometheus"
CONFIG_DIR="/etc/prometheus"
DATA_DIR="/var/lib/prometheus"
BIN_DIR="/usr/local/bin"
DOWNLOAD_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

# AWS Configuration for EC2 Service Discovery
AWS_REGION="ap-south-1"
IAM_ROLE_ARN="arn:aws:iam::638845738277:role/ROLE-IIFL-FINALYZER-PROM-GRAFANA-MONITOR"
AWS_ACCOUNT_TAG="finalyzer-360one"

# Data retention period
RETENTION_DAYS="30d"

# Ports for exporters
NODE_EXPORTER_PORT="9100"
JMX_EXPORTER_PORT="1098"
MYSQL_EXPORTER_PORT="9104"

#-------------------------------------------------------------------------------
# HELPER FUNCTIONS
#-------------------------------------------------------------------------------

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    case $color in
        "green")  echo -e "\e[32m[SUCCESS]\e[0m $message" ;;
        "red")    echo -e "\e[31m[ERROR]\e[0m $message" ;;
        "yellow") echo -e "\e[33m[WARNING]\e[0m $message" ;;
        "blue")   echo -e "\e[34m[INFO]\e[0m $message" ;;
    esac
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_message "red" "This script must be run as root or with sudo"
        exit 1
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to cleanup on error
cleanup_on_error() {
    print_message "red" "Installation failed. Cleaning up..."
    rm -rf "${INSTALL_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" 2>/dev/null
    rm -rf "${INSTALL_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64" 2>/dev/null
    exit 1
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

#-------------------------------------------------------------------------------
# PRE-INSTALLATION CHECKS
#-------------------------------------------------------------------------------

print_message "blue" "Starting Prometheus ${PROMETHEUS_VERSION} installation..."

# Check if running as root
check_root

# Check if Prometheus is already installed
if command_exists prometheus; then
    CURRENT_VERSION=$(prometheus --version 2>&1 | head -1 | awk '{print $3}')
    print_message "yellow" "Prometheus is already installed (version: ${CURRENT_VERSION})"
    read -p "Do you want to continue with reinstallation? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "blue" "Installation cancelled by user"
        exit 0
    fi
    # Stop existing service if running
    systemctl stop prometheus 2>/dev/null || true
fi

# Check for required tools
for cmd in wget tar; do
    if ! command_exists $cmd; then
        print_message "red" "Required command '$cmd' not found. Please install it first."
        exit 1
    fi
done

#-------------------------------------------------------------------------------
# CREATE PROMETHEUS USER AND DIRECTORIES
#-------------------------------------------------------------------------------

print_message "blue" "Creating Prometheus user and directories..."

# Create prometheus user (system account with no login shell)
if ! id "${PROMETHEUS_USER}" &>/dev/null; then
    useradd --no-create-home --shell /bin/false "${PROMETHEUS_USER}"
    print_message "green" "Created user: ${PROMETHEUS_USER}"
else
    print_message "yellow" "User ${PROMETHEUS_USER} already exists"
fi

# Create required directories
mkdir -p "${INSTALL_DIR}"
mkdir -p "${CONFIG_DIR}"
mkdir -p "${CONFIG_DIR}/consoles"
mkdir -p "${CONFIG_DIR}/console_libraries"
mkdir -p "${CONFIG_DIR}/rules"
mkdir -p "${DATA_DIR}"

print_message "green" "Directories created successfully"

#-------------------------------------------------------------------------------
# DOWNLOAD AND EXTRACT PROMETHEUS
#-------------------------------------------------------------------------------

print_message "blue" "Downloading Prometheus ${PROMETHEUS_VERSION}..."

cd "${INSTALL_DIR}"

# Download Prometheus if not already downloaded
TARBALL="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
if [[ ! -f "${TARBALL}" ]]; then
    wget -q --show-progress "${DOWNLOAD_URL}" -O "${TARBALL}"
    print_message "green" "Download completed"
else
    print_message "yellow" "Tarball already exists, skipping download"
fi

# Extract the tarball
print_message "blue" "Extracting Prometheus..."
tar -xzf "${TARBALL}"

# Define extracted directory name
EXTRACTED_DIR="prometheus-${PROMETHEUS_VERSION}.linux-amd64"

#-------------------------------------------------------------------------------
# INSTALL PROMETHEUS BINARIES
#-------------------------------------------------------------------------------

print_message "blue" "Installing Prometheus binaries..."

# Copy binaries to /usr/local/bin
cp "${INSTALL_DIR}/${EXTRACTED_DIR}/prometheus" "${BIN_DIR}/"
cp "${INSTALL_DIR}/${EXTRACTED_DIR}/promtool" "${BIN_DIR}/"

# Set ownership for binaries
chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${BIN_DIR}/prometheus"
chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${BIN_DIR}/promtool"

# Make binaries executable
chmod +x "${BIN_DIR}/prometheus"
chmod +x "${BIN_DIR}/promtool"

# Copy console files
cp -r "${INSTALL_DIR}/${EXTRACTED_DIR}/consoles/"* "${CONFIG_DIR}/consoles/" 2>/dev/null || true
cp -r "${INSTALL_DIR}/${EXTRACTED_DIR}/console_libraries/"* "${CONFIG_DIR}/console_libraries/" 2>/dev/null || true

print_message "green" "Binaries installed successfully"

#-------------------------------------------------------------------------------
# CREATE PROMETHEUS CONFIGURATION FILE
#-------------------------------------------------------------------------------

print_message "blue" "Creating Prometheus configuration..."

cat > "${CONFIG_DIR}/prometheus.yml" <<EOF
#===============================================================================
# Prometheus Configuration File
#===============================================================================
# Generated by: install_prometheus.sh
# Generated on: $(date '+%Y-%m-%d %H:%M:%S')
# Prometheus Version: ${PROMETHEUS_VERSION}
#===============================================================================

# Global configuration
global:
  scrape_interval: 15s          # How frequently to scrape targets
  evaluation_interval: 15s      # How frequently to evaluate rules
  scrape_timeout: 10s           # Timeout for scraping targets
  
  # Attach these labels to any time series or alerts when communicating with
  # external systems (federation, remote storage, Alertmanager)
  external_labels:
    monitor: 'prometheus-server'
    environment: 'production'

#-------------------------------------------------------------------------------
# Alertmanager Configuration
#-------------------------------------------------------------------------------
alerting:
  alertmanagers:
    - static_configs:
        - targets: []
          # Uncomment and configure when Alertmanager is set up
          # - targets: ['localhost:9093']

#-------------------------------------------------------------------------------
# Rule Files Configuration
#-------------------------------------------------------------------------------
# Load rules once and periodically evaluate them according to 'evaluation_interval'
rule_files:
  # Uncomment when alert rules are configured
  # - '/etc/prometheus/rules/*.yml'

#-------------------------------------------------------------------------------
# Scrape Configurations
#-------------------------------------------------------------------------------
scrape_configs:

  #-----------------------------------------------------------------------------
  # Job: Prometheus Self-Monitoring
  #-----------------------------------------------------------------------------
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance_name: 'prometheus-server'

  #-----------------------------------------------------------------------------
  # Job: Local Node Exporter (Monitoring Server)
  #-----------------------------------------------------------------------------
  - job_name: 'monitoring_server_node'
    static_configs:
      - targets: ['localhost:${NODE_EXPORTER_PORT}']
        labels:
          instance_name: 'monitoring-server'
          environment: 'production'

  #-----------------------------------------------------------------------------
  # Job: Node Exporter - EC2 Service Discovery
  #-----------------------------------------------------------------------------
  # Discovers EC2 instances with tag Prometheus_jmx=true OR Prometheus_mysql=true
  - job_name: 'node_exporter'
    ec2_sd_configs:
      - region: '${AWS_REGION}'
        role_arn: '${IAM_ROLE_ARN}'
        port: ${NODE_EXPORTER_PORT}
        refresh_interval: 5m
        filters:
          # Filter instances by AWS account tag
          - name: 'tag:AWS_Account'
            values: ['${AWS_ACCOUNT_TAG}']
    
    relabel_configs:
      # Keep only instances with Prometheus_jmx=true OR Prometheus_mysql=true
      - source_labels: [__meta_ec2_tag_Prometheus_jmx, __meta_ec2_tag_Prometheus_mysql]
        separator: ';'
        regex: 'true;.*|.*;true'
        action: keep

      # Set instance name from EC2 Name tag
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name

      # Set environment label from EC2 tag
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

  #-----------------------------------------------------------------------------
  # Job: JMX Exporter - EC2 Service Discovery
  #-----------------------------------------------------------------------------
  # Discovers EC2 instances with tag Prometheus_jmx=true
  - job_name: 'jmx_exporter'
    ec2_sd_configs:
      - region: '${AWS_REGION}'
        role_arn: '${IAM_ROLE_ARN}'
        port: ${JMX_EXPORTER_PORT}
        refresh_interval: 5m
        filters:
          - name: 'tag:AWS_Account'
            values: ['${AWS_ACCOUNT_TAG}']
          - name: 'tag:Prometheus_jmx'
            values: ['true']
    
    relabel_configs:
      # Set instance name from EC2 Name tag
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name

      # Set environment label
      - source_labels: [__meta_ec2_tag_Environment]
        target_label: environment

      # Set target address using private IP with JMX port
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '\${1}:${JMX_EXPORTER_PORT}'

      # Add availability zone label
      - source_labels: [__meta_ec2_availability_zone]
        target_label: availability_zone

      # Add instance type label
      - source_labels: [__meta_ec2_instance_type]
        target_label: instance_type

      # Add instance ID label
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id

  #-----------------------------------------------------------------------------
  # Job: MySQL Exporter - EC2 Service Discovery
  #-----------------------------------------------------------------------------
  # Discovers EC2 instances with tag Prometheus_mysql=true
  - job_name: 'mysql_exporter'
    ec2_sd_configs:
      - region: '${AWS_REGION}'
        role_arn: '${IAM_ROLE_ARN}'
        port: ${MYSQL_EXPORTER_PORT}
        refresh_interval: 5m
        filters:
          - name: 'tag:AWS_Account'
            values: ['${AWS_ACCOUNT_TAG}']
          - name: 'tag:Prometheus_mysql'
            values: ['true']
    
    relabel_configs:
      # Set instance name from EC2 Name tag
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name

      # Set environment label
      - source_labels: [__meta_ec2_tag_Environment]
        target_label: environment

      # Set target address using private IP with MySQL exporter port
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '\${1}:${MYSQL_EXPORTER_PORT}'

      # Add availability zone label
      - source_labels: [__meta_ec2_availability_zone]
        target_label: availability_zone

      # Add instance type label
      - source_labels: [__meta_ec2_instance_type]
        target_label: instance_type

      # Add instance ID label
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
EOF

print_message "green" "Configuration file created"

#-------------------------------------------------------------------------------
# SET PERMISSIONS
#-------------------------------------------------------------------------------

print_message "blue" "Setting permissions..."

# Set ownership for all Prometheus directories and files
chown -R "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${CONFIG_DIR}"
chown -R "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${DATA_DIR}"

# Set appropriate permissions
chmod 755 "${CONFIG_DIR}"
chmod 644 "${CONFIG_DIR}/prometheus.yml"
chmod 755 "${DATA_DIR}"

print_message "green" "Permissions set successfully"

#-------------------------------------------------------------------------------
# VALIDATE CONFIGURATION
#-------------------------------------------------------------------------------

print_message "blue" "Validating Prometheus configuration..."

if "${BIN_DIR}/promtool" check config "${CONFIG_DIR}/prometheus.yml"; then
    print_message "green" "Configuration validation passed"
else
    print_message "red" "Configuration validation failed!"
    exit 1
fi

#-------------------------------------------------------------------------------
# CREATE SYSTEMD SERVICE FILE
#-------------------------------------------------------------------------------

print_message "blue" "Creating systemd service..."

cat > /etc/systemd/system/prometheus.service <<EOF
#===============================================================================
# Prometheus Systemd Service File
#===============================================================================
# Generated by: install_prometheus.sh
# Generated on: $(date '+%Y-%m-%d %H:%M:%S')
#===============================================================================

[Unit]
Description=Prometheus Monitoring System
Documentation=https://prometheus.io/docs/introduction/overview/
Wants=network-online.target
After=network-online.target

[Service]
User=${PROMETHEUS_USER}
Group=${PROMETHEUS_GROUP}
Type=simple

# Prometheus startup command with all necessary flags
ExecStart=${BIN_DIR}/prometheus \\
    --config.file=${CONFIG_DIR}/prometheus.yml \\
    --storage.tsdb.path=${DATA_DIR} \\
    --storage.tsdb.retention.time=${RETENTION_DAYS} \\
    --web.console.templates=${CONFIG_DIR}/consoles \\
    --web.console.libraries=${CONFIG_DIR}/console_libraries \\
    --web.listen-address=0.0.0.0:9090 \\
    --web.enable-lifecycle \\
    --web.enable-admin-api \\
    --log.level=info

# Restart policy
Restart=on-failure
RestartSec=5s

# Security hardening
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes

# Resource limits (adjust based on your needs)
LimitNOFILE=65536

# Standard output and error logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=prometheus

[Install]
WantedBy=multi-user.target
EOF

# Set proper permissions for service file
chmod 644 /etc/systemd/system/prometheus.service

print_message "green" "Systemd service created"

#-------------------------------------------------------------------------------
# START PROMETHEUS SERVICE
#-------------------------------------------------------------------------------

print_message "blue" "Starting Prometheus service..."

# Reload systemd daemon to recognize new service
systemctl daemon-reload

# Enable Prometheus to start on boot
systemctl enable prometheus

# Start Prometheus service
systemctl start prometheus

# Wait a moment for the service to start
sleep 3

# Check if service started successfully
if systemctl is-active --quiet prometheus; then
    print_message "green" "Prometheus service started successfully"
else
    print_message "red" "Failed to start Prometheus service"
    print_message "blue" "Checking service logs..."
    journalctl -u prometheus --no-pager -n 20
    exit 1
fi

#-------------------------------------------------------------------------------
# CLEANUP
#-------------------------------------------------------------------------------

print_message "blue" "Cleaning up installation files..."

rm -f "${INSTALL_DIR}/${TARBALL}"
rm -rf "${INSTALL_DIR}/${EXTRACTED_DIR}"

print_message "green" "Cleanup completed"

#-------------------------------------------------------------------------------
# CONFIGURE FIREWALL (if firewalld is active)
#-------------------------------------------------------------------------------

if systemctl is-active --quiet firewalld; then
    print_message "blue" "Configuring firewall..."
    firewall-cmd --permanent --add-port=9090/tcp
    firewall-cmd --reload
    print_message "green" "Firewall configured"
else
    print_message "yellow" "Firewalld not active, skipping firewall configuration"
fi

#-------------------------------------------------------------------------------
# INSTALLATION SUMMARY
#-------------------------------------------------------------------------------

# Get installed version
INSTALLED_VERSION=$("${BIN_DIR}/prometheus" --version 2>&1 | head -1)

echo ""
echo "==============================================================================="
echo "                    PROMETHEUS INSTALLATION COMPLETE"
echo "==============================================================================="
echo ""
echo "  Version:          ${PROMETHEUS_VERSION}"
echo "  Binary Location:  ${BIN_DIR}/prometheus"
echo "  Config File:      ${CONFIG_DIR}/prometheus.yml"
echo "  Data Directory:   ${DATA_DIR}"
echo "  Service Name:     prometheus"
echo "  Retention:        ${RETENTION_DAYS}"
echo ""
echo "  Web UI:           http://<server-ip>:9090"
echo "  Targets:          http://<server-ip>:9090/targets"
echo "  Config:           http://<server-ip>:9090/config"
echo ""
echo "==============================================================================="
echo "                         USEFUL COMMANDS"
echo "==============================================================================="
echo ""
echo "  Check version:      prometheus --version"
echo "  Service status:     sudo systemctl status prometheus"
echo "  View logs:          sudo journalctl -u prometheus -f"
echo "  Restart service:    sudo systemctl restart prometheus"
echo "  Validate config:    promtool check config ${CONFIG_DIR}/prometheus.yml"
echo "  Reload config:      curl -X POST http://localhost:9090/-/reload"
echo ""
echo "==============================================================================="
echo ""

# Final verification
print_message "blue" "Verifying installation..."
echo ""
echo "Prometheus Version:"
"${BIN_DIR}/prometheus" --version 2>&1 | head -3
echo ""
echo "Service Status:"
systemctl status prometheus --no-pager -l | head -10
echo ""

print_message "green" "Installation completed successfully!"
