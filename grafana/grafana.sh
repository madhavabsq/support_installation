#!/bin/bash

#===============================================================================
#
#          FILE: install_grafana.sh
#
#         USAGE: sudo ./install_grafana.sh
#
#   DESCRIPTION: Automated installation script for Grafana OSS on
#                Amazon Linux 2023 / RHEL 8+ / CentOS Stream / Fedora
#                using DNF package manager
#
#        AUTHOR: Infrastructure Team
#       VERSION: 1.0.0
#       CREATED: 2025
#
#  REQUIREMENTS: - Root/sudo access
#                - Internet connectivity
#                - DNF package manager
#                - RHEL 8+ / Amazon Linux 2023 / CentOS Stream 8+
#
#         NOTES: This script is idempotent - safe to run multiple times
#                Default credentials: admin / admin
#
#===============================================================================

#-------------------------------------------------------------------------------
# BASH STRICT MODE
#-------------------------------------------------------------------------------
# -e          : Exit immediately if any command returns non-zero exit status
# -u          : Treat unset variables as errors
# -o pipefail : Return value of pipeline is status of last command to exit non-zero
#-------------------------------------------------------------------------------
set -e
set -u
set -o pipefail

#-------------------------------------------------------------------------------
# CONFIGURATION VARIABLES
#-------------------------------------------------------------------------------
# Modify these variables according to your environment
#-------------------------------------------------------------------------------

# Grafana repository configuration
GRAFANA_REPO_NAME="grafana"
GRAFANA_REPO_DESCRIPTION="Grafana OSS"
GRAFANA_REPO_BASEURL="https://packages.grafana.com/oss/rpm"
GRAFANA_GPG_KEY="https://packages.grafana.com/gpg.key"

# For Grafana Enterprise, use these instead:
# GRAFANA_REPO_BASEURL="https://packages.grafana.com/enterprise/rpm"

# Grafana service configuration
GRAFANA_PORT="3000"                      # Default Grafana web port
GRAFANA_USER="grafana"                   # Service user (created by package)
GRAFANA_GROUP="grafana"                  # Service group (created by package)

# File paths
GRAFANA_CONFIG="/etc/grafana/grafana.ini"
GRAFANA_LOG_DIR="/var/log/grafana"
GRAFANA_DATA_DIR="/var/lib/grafana"
GRAFANA_PLUGINS_DIR="/var/lib/grafana/plugins"
REPO_FILE="/etc/yum.repos.d/grafana.repo"

# Default admin credentials (change after first login!)
DEFAULT_ADMIN_USER="admin"
DEFAULT_ADMIN_PASS="admin"

# Provisioning directories
GRAFANA_PROVISIONING_DIR="/etc/grafana/provisioning"
GRAFANA_DASHBOARDS_DIR="${GRAFANA_PROVISIONING_DIR}/dashboards"
GRAFANA_DATASOURCES_DIR="${GRAFANA_PROVISIONING_DIR}/datasources"

# Optional: Prometheus data source configuration
PROMETHEUS_URL="http://localhost:9090"   # URL of your Prometheus server
CONFIGURE_PROMETHEUS_DS="false"          # Set to "true" to auto-configure

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
# Why needed: Installing packages and system services requires root
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
# Function: check_os_compatibility
# Description: Verify the OS is compatible (RHEL-based with DNF)
# Why needed: Script uses DNF package manager
#
check_os_compatibility() {
    log_info "Checking OS compatibility..."
    
    # Check if DNF is available
    if ! command_exists dnf; then
        log_error "DNF package manager not found"
        log_info "This script requires RHEL 8+, Amazon Linux 2023, CentOS Stream 8+, or Fedora"
        exit 1
    fi
    
    # Get OS information
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        log_info "Detected OS: ${NAME} ${VERSION_ID}"
    else
        log_warn "Could not detect OS version"
    fi
    
    log_success "OS compatibility check passed"
}

#
# Function: check_existing_installation
# Description: Detect if Grafana is already installed
#
check_existing_installation() {
    log_info "Checking for existing Grafana installation..."
    
    if rpm -q grafana &>/dev/null; then
        local current_version
        current_version=$(rpm -q grafana --queryformat '%{VERSION}')
        
        log_warn "Grafana is already installed (version: ${current_version})"
        read -p "Do you want to proceed with reinstallation/upgrade? (y/n): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled by user"
            exit 0
        fi
        
        log_info "Stopping existing Grafana service..."
        systemctl stop grafana-server 2>/dev/null || true
    else
        log_success "No existing Grafana installation found"
    fi
}

#
# Function: cleanup_on_error
# Description: Clean up if installation fails
#
cleanup_on_error() {
    log_error "Installation failed! Please check the error messages above."
    log_info "You can check logs with: journalctl -u grafana-server -n 50"
    exit 1
}

#-------------------------------------------------------------------------------
# INSTALLATION FUNCTIONS
#-------------------------------------------------------------------------------

#
# Function: create_grafana_repo
# Description: Create the Grafana YUM/DNF repository file
# Why needed: Grafana is not in default repositories
#
# Repository options explained:
# - repo_gpgcheck=1: Verify repository metadata signature
# - gpgcheck=1: Verify package signatures
# - sslverify=1: Verify SSL certificates
# - sslcacert: Path to CA certificate bundle
#
create_grafana_repo() {
    log_section "Creating Grafana Repository"
    
    log_info "Creating repository file: ${REPO_FILE}"
    
    # Create repository configuration file
    cat > "${REPO_FILE}" <<EOF
#===============================================================================
# Grafana OSS Repository
#===============================================================================
# Auto-generated by: install_grafana.sh
# Generated on:      $(date '+%Y-%m-%d %H:%M:%S')
#
# Documentation: https://grafana.com/docs/grafana/latest/setup-grafana/installation/rpm/
#===============================================================================

[${GRAFANA_REPO_NAME}]
# Repository name displayed in DNF
name=${GRAFANA_REPO_DESCRIPTION}

# Base URL for RPM packages
baseurl=${GRAFANA_REPO_BASEURL}

# Verify repository metadata GPG signature
repo_gpgcheck=1

# Enable this repository
enabled=1

# Verify package GPG signatures
gpgcheck=1

# URL to GPG public key for signature verification
gpgkey=${GRAFANA_GPG_KEY}

# Enable SSL certificate verification
sslverify=1

# Path to CA certificate bundle for SSL verification
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

    # Set appropriate permissions (readable by all, writable by root)
    chmod 644 "${REPO_FILE}"
    
    log_success "Repository file created: ${REPO_FILE}"
}

#
# Function: import_gpg_key
# Description: Import Grafana's GPG key for package verification
# Why needed: Ensures packages are authentic and unmodified
#
import_gpg_key() {
    log_section "Importing GPG Key"
    
    log_info "Importing Grafana GPG key from: ${GRAFANA_GPG_KEY}"
    
    # rpm --import downloads and imports the GPG key
    if rpm --import "${GRAFANA_GPG_KEY}"; then
        log_success "GPG key imported successfully"
    else
        log_error "Failed to import GPG key"
        exit 1
    fi
    
    # Verify key was imported
    if rpm -qa gpg-pubkey* | grep -q gpg-pubkey; then
        log_info "GPG keys currently installed:"
        rpm -qa gpg-pubkey* --queryformat '%{NAME}-%{VERSION} %{SUMMARY}\n' | head -5 || true
    fi
}

#
# Function: update_package_cache
# Description: Update DNF package cache to include new repository
# Why needed: DNF needs to fetch repository metadata
#
update_package_cache() {
    log_section "Updating Package Cache"
    
    log_info "Refreshing DNF cache..."
    
    # makecache downloads and caches repository metadata
    # -y flag assumes yes to any prompts
    if dnf -y makecache; then
        log_success "Package cache updated successfully"
    else
        log_error "Failed to update package cache"
        exit 1
    fi
}

#
# Function: install_grafana
# Description: Install Grafana package using DNF
#
install_grafana() {
    log_section "Installing Grafana"
    
    log_info "Installing Grafana package..."
    
    # Install Grafana with automatic yes to prompts
    if dnf -y install grafana; then
        log_success "Grafana package installed successfully"
    else
        log_error "Failed to install Grafana"
        exit 1
    fi
    
    # Display installed version
    local installed_version
    installed_version=$(rpm -q grafana --queryformat '%{VERSION}-%{RELEASE}')
    log_info "Installed version: ${installed_version}"
}

#
# Function: configure_grafana
# Description: Apply basic Grafana configuration
# Why needed: Set up initial configuration for production use
#
configure_grafana() {
    log_section "Configuring Grafana"
    
    # Backup original config if it exists and no backup exists
    if [[ -f "${GRAFANA_CONFIG}" ]] && [[ ! -f "${GRAFANA_CONFIG}.backup" ]]; then
        log_info "Creating backup of original configuration..."
        cp "${GRAFANA_CONFIG}" "${GRAFANA_CONFIG}.backup"
        log_success "Backup created: ${GRAFANA_CONFIG}.backup"
    fi
    
    # Create provisioning directories if they don't exist
    log_info "Creating provisioning directories..."
    mkdir -p "${GRAFANA_DASHBOARDS_DIR}"
    mkdir -p "${GRAFANA_DATASOURCES_DIR}"
    
    # Set correct ownership
    chown -R "${GRAFANA_USER}:${GRAFANA_GROUP}" "${GRAFANA_PROVISIONING_DIR}"
    
    log_success "Grafana configuration completed"
    
    # Optionally configure Prometheus data source
    if [[ "${CONFIGURE_PROMETHEUS_DS}" == "true" ]]; then
        configure_prometheus_datasource
    fi
}

#
# Function: configure_prometheus_datasource
# Description: Auto-configure Prometheus as a data source
# Why needed: Enables immediate visualization of Prometheus metrics
#
configure_prometheus_datasource() {
    log_info "Configuring Prometheus data source..."
    
    cat > "${GRAFANA_DATASOURCES_DIR}/prometheus.yml" <<EOF
#===============================================================================
# Prometheus Data Source Configuration
#===============================================================================
# Auto-generated by: install_grafana.sh
# Generated on:      $(date '+%Y-%m-%d %H:%M:%S')
#===============================================================================

apiVersion: 1

# List of data sources to configure
datasources:
  # Prometheus data source
  - name: Prometheus
    type: prometheus
    access: proxy
    url: ${PROMETHEUS_URL}
    isDefault: true
    editable: true
    jsonData:
      # Time interval for scrape (should match Prometheus scrape_interval)
      timeInterval: "15s"
      # HTTP method for queries
      httpMethod: "POST"
      # Enable exemplars (if using tracing)
      exemplarTraceIdDestinations: []
EOF

    chown "${GRAFANA_USER}:${GRAFANA_GROUP}" "${GRAFANA_DATASOURCES_DIR}/prometheus.yml"
    chmod 640 "${GRAFANA_DATASOURCES_DIR}/prometheus.yml"
    
    log_success "Prometheus data source configured"
}

#
# Function: setup_systemd
# Description: Configure and enable Grafana systemd service
#
setup_systemd() {
    log_section "Setting Up Systemd Service"
    
    # Reload systemd to recognize any changes
    log_info "Reloading systemd daemon..."
    systemctl daemon-reload
    
    # Enable Grafana to start on boot
    log_info "Enabling Grafana service for auto-start..."
    systemctl enable grafana-server
    
    # Start Grafana service
    log_info "Starting Grafana service..."
    systemctl start grafana-server
    
    # Wait for service to initialize
    log_info "Waiting for service to initialize..."
    sleep 5
    
    # Verify service is running
    if systemctl is-active --quiet grafana-server; then
        log_success "Grafana service is running"
    else
        log_error "Grafana service failed to start"
        log_info "Checking service logs..."
        journalctl -u grafana-server --no-pager -n 30
        exit 1
    fi
}

#
# Function: install_firewalld
# Description: Ensure firewalld is installed
# Why needed: May not be installed on minimal installations
#
install_firewalld() {
    log_section "Configuring Firewall"
    
    # Check if firewalld is installed
    if ! rpm -q firewalld &>/dev/null; then
        log_info "Firewalld not found, installing..."
        if dnf -y install firewalld; then
            log_success "Firewalld installed successfully"
        else
            log_warn "Failed to install firewalld, skipping firewall configuration"
            return 1
        fi
    else
        log_info "Firewalld is already installed"
    fi
    
    return 0
}

#
# Function: configure_firewall
# Description: Configure firewall to allow Grafana port
#
configure_firewall() {
    # Install firewalld if not present
    if ! install_firewalld; then
        return
    fi
    
    # Enable and start firewalld if not running
    if ! systemctl is-active --quiet firewalld; then
        log_info "Starting firewalld service..."
        systemctl enable --now firewalld
    fi
    
    # Check if port is already open
    if firewall-cmd --query-port=${GRAFANA_PORT}/tcp &>/dev/null; then
        log_info "Port ${GRAFANA_PORT}/tcp is already open"
    else
        # Add Grafana port to firewall
        log_info "Opening port ${GRAFANA_PORT}/tcp..."
        firewall-cmd --permanent --add-port=${GRAFANA_PORT}/tcp
        
        # Reload firewall to apply changes
        log_info "Reloading firewall rules..."
        firewall-cmd --reload
        
        log_success "Firewall configured - port ${GRAFANA_PORT}/tcp opened"
    fi
}

#
# Function: install_common_plugins
# Description: Install commonly used Grafana plugins
# Why needed: Extends Grafana functionality
#
install_common_plugins() {
    log_section "Installing Grafana Plugins (Optional)"
    
    # List of commonly used plugins
    # Uncomment the plugins you want to install
    local plugins=(
        # "grafana-clock-panel"           # Clock panel
        # "grafana-piechart-panel"        # Pie chart panel
        # "grafana-worldmap-panel"        # World map panel
        # "grafana-polystat-panel"        # Polystat panel
        # "grafana-image-renderer"        # Image renderer for alerts
    )
    
    if [[ ${#plugins[@]} -eq 0 ]]; then
        log_info "No plugins configured for installation"
        log_info "Edit the script to enable plugin installation"
        return
    fi
    
    for plugin in "${plugins[@]}"; do
        log_info "Installing plugin: ${plugin}"
        if grafana-cli plugins install "${plugin}" 2>/dev/null; then
            log_success "Plugin installed: ${plugin}"
        else
            log_warn "Failed to install plugin: ${plugin}"
        fi
    done
    
    # Restart Grafana to load new plugins
    log_info "Restarting Grafana to load plugins..."
    systemctl restart grafana-server
    sleep 3
}

#
# Function: print_summary
# Description: Display installation summary and useful information
#
print_summary() {
    # Get installed version safely
    local installed_version
    installed_version=$(rpm -q grafana --queryformat '%{VERSION}' 2>/dev/null) || installed_version="Unknown"
    
    # Get server IP safely
    local server_ip
    server_ip=$(hostname -I 2>/dev/null | awk '{print $1}') || server_ip="<server-ip>"
    
    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}         GRAFANA INSTALLATION COMPLETED SUCCESSFULLY${NC}"
    echo "==============================================================================="
    echo ""
    echo "  Installation Details:"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    echo "  Version:            ${installed_version}"
    echo "  Config File:        ${GRAFANA_CONFIG}"
    echo "  Data Directory:     ${GRAFANA_DATA_DIR}"
    echo "  Log Directory:      ${GRAFANA_LOG_DIR}"
    echo "  Plugins Directory:  ${GRAFANA_PLUGINS_DIR}"
    echo "  Service Name:       grafana-server"
    echo "  Running As:         ${GRAFANA_USER}:${GRAFANA_GROUP}"
    echo ""
    echo "  Access URLs:"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    echo "  Web UI:             http://${server_ip}:${GRAFANA_PORT}"
    echo "  Login:              http://${server_ip}:${GRAFANA_PORT}/login"
    echo "  API Health:         http://${server_ip}:${GRAFANA_PORT}/api/health"
    echo "  API Datasources:    http://${server_ip}:${GRAFANA_PORT}/api/datasources"
    echo ""
    echo "  Default Credentials (CHANGE IMMEDIATELY!):"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    echo "  Username:           ${DEFAULT_ADMIN_USER}"
    echo "  Password:           ${DEFAULT_ADMIN_PASS}"
    echo ""
    echo -e "  ${RED}⚠️  IMPORTANT: Change the admin password after first login!${NC}"
    echo ""
    echo "  Useful Commands:"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    echo "  Check version:      grafana-server -v"
    echo "  Service status:     sudo systemctl status grafana-server"
    echo "  View logs:          sudo journalctl -u grafana-server -f"
    echo "  Restart service:    sudo systemctl restart grafana-server"
    echo "  Stop service:       sudo systemctl stop grafana-server"
    echo "  View log file:      sudo tail -f ${GRAFANA_LOG_DIR}/grafana.log"
    echo "  Install plugin:     sudo grafana-cli plugins install <plugin-name>"
    echo "  List plugins:       sudo grafana-cli plugins ls"
    echo "  Reset admin pass:   sudo grafana-cli admin reset-admin-password <new-pass>"
    echo ""
    echo "  Configuration Files:"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    echo "  Main config:        ${GRAFANA_CONFIG}"
    echo "  Provisioning:       ${GRAFANA_PROVISIONING_DIR}/"
    echo "  Data sources:       ${GRAFANA_DATASOURCES_DIR}/"
    echo "  Dashboards:         ${GRAFANA_DASHBOARDS_DIR}/"
    echo ""
    echo "  Next Steps:"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    echo "  1. Open http://${server_ip}:${GRAFANA_PORT} in your browser"
    echo "  2. Login with admin/admin"
    echo "  3. Change the admin password when prompted"
    echo "  4. Add data sources (Prometheus, MySQL, etc.)"
    echo "  5. Import or create dashboards"
    echo ""
    if [[ "${CONFIGURE_PROMETHEUS_DS}" == "true" ]]; then
        echo "  Prometheus Data Source:"
        echo "  ─────────────────────────────────────────────────────────────────────────────"
        echo "  ✓ Prometheus data source auto-configured"
        echo "  URL: ${PROMETHEUS_URL}"
        echo ""
    fi
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
    echo "Grafana Version:"
    # Use subshell with || true to prevent errors
    (grafana-server -v 2>&1 || true)
    echo ""
    
    echo "Service Status:"
    # Store output in variable to avoid pipe issues
    local status_output
    status_output=$(systemctl status grafana-server --no-pager 2>&1 || true)
    echo "${status_output}" | head -15
    echo ""
    
    echo "HTTP Health Check:"
    # Check if Grafana is responding
    local http_response
    http_response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${GRAFANA_PORT}/api/health" 2>/dev/null || echo "000")
    if [[ "${http_response}" == "200" ]]; then
        echo -e "${GREEN}✓ Grafana is responding (HTTP ${http_response})${NC}"
    else
        echo -e "${YELLOW}⚠ Grafana HTTP check returned: ${http_response}${NC}"
        echo "  This may be normal if Grafana is still starting up"
    fi
    echo ""
    
    echo "Recent Log Entries:"
    # Show recent log entries
    if [[ -f "${GRAFANA_LOG_DIR}/grafana.log" ]]; then
        tail -n 10 "${GRAFANA_LOG_DIR}/grafana.log" 2>/dev/null || true
    else
        echo "Log file not found yet (Grafana may still be starting)"
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# MAIN EXECUTION
#-------------------------------------------------------------------------------

main() {
    log_section "Grafana Installation Script"
    
    # Set up error trap for cleanup during critical installation steps
    trap cleanup_on_error ERR
    
    # Pre-installation checks
    check_root
    check_os_compatibility
    check_existing_installation
    
    # Installation steps
    create_grafana_repo
    import_gpg_key
    update_package_cache
    install_grafana
    configure_grafana
    setup_systemd
    configure_firewall
    
    # Optional: Install plugins
    # Uncomment the following line to install common plugins
    # install_common_plugins
    
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
    
    log_success "Grafana installation completed successfully!"
}

# Run main function with all script arguments
main "$@"