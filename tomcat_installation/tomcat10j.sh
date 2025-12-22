#!/bin/bash
###############################################################################
# Script Name  : install_tomcat10.sh
# Description  : Installs Apache Tomcat 10 on Amazon Linux 2023 / RHEL
#                Creates tomcat user, configures systemd service, and
#                sets appropriate permissions.
# Usage        : sudo ./install_tomcat10.sh
# Prerequisites: Root or sudo access, internet connectivity, Java 21 installed
# Log Location : /var/log/tomcat10_install_<timestamp>.log
###############################################################################

set -euo pipefail

###############################################################################
# Configuration
###############################################################################
TOMCAT_VERSION="10.1.49"
TOMCAT_FILE="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_DIR="tomcat10"
TOMCAT_HOME="/usr/share/${TOMCAT_DIR}"
TOMCAT_DOWNLOAD_URL="https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/${TOMCAT_FILE}"
JAVA_HOME="/usr/lib/jvm/java-21-amazon-corretto"

LOG_DIR="/var/log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/tomcat10_install_${TIMESTAMP}.log"

###############################################################################
# Setup logging
# All output (stdout and stderr) will be sent to both console and log file
###############################################################################
setup_logging() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    
    exec > >(tee -a "$LOG_FILE") 2>&1
    
    echo "============================================================================="
    echo "Apache Tomcat ${TOMCAT_VERSION} Installation Log"
    echo "============================================================================="
    echo "Timestamp       : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Hostname        : $(hostname)"
    echo "OS Version      : $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "Log File        : $LOG_FILE"
    echo "============================================================================="
    echo ""
}

###############################################################################
# Logging helper function
# Usage: log_msg "INFO" "Your message here"
#        log_msg "ERROR" "Something went wrong"
###############################################################################
log_msg() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

###############################################################################
# Error handler
###############################################################################
error_exit() {
    log_msg "ERROR" "$1"
    log_msg "ERROR" "Installation failed. Check log file: $LOG_FILE"
    exit 1
}

###############################################################################
# Check prerequisites
###############################################################################
check_prerequisites() {
    log_msg "INFO" "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root or with sudo"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 dlcdn.apache.org &>/dev/null; then
        error_exit "No internet connectivity to dlcdn.apache.org"
    fi
    
    # Check if Java is installed
    if [[ ! -d "$JAVA_HOME" ]]; then
        error_exit "Java not found at $JAVA_HOME. Please install Java 21 first."
    fi
    
    log_msg "INFO" "Prerequisites check passed"
}

###############################################################################
# Update system packages
###############################################################################
update_system() {
    log_msg "INFO" "Updating system packages..."
    dnf update -y
    log_msg "INFO" "System packages updated"
}

###############################################################################
# Create tomcat user and group
###############################################################################
create_tomcat_user() {
    log_msg "INFO" "Creating tomcat group and user..."
    
    if ! getent group tomcat &>/dev/null; then
        groupadd tomcat
        log_msg "INFO" "Tomcat group created"
    else
        log_msg "INFO" "Tomcat group already exists, skipping..."
    fi
    
    if ! id tomcat &>/dev/null; then
        useradd -M -s /usr/sbin/nologin -g tomcat -d "${TOMCAT_HOME}" tomcat
        log_msg "INFO" "Tomcat user created"
    else
        log_msg "INFO" "Tomcat user already exists, skipping..."
    fi
}

###############################################################################
# Download Apache Tomcat
###############################################################################
download_tomcat() {
    log_msg "INFO" "Downloading Apache Tomcat ${TOMCAT_VERSION}..."
    
    cd /tmp
    
    if [[ -f "${TOMCAT_FILE}" ]]; then
        log_msg "INFO" "Tomcat archive already exists in /tmp, removing old file..."
        rm -f "${TOMCAT_FILE}"
    fi
    
    wget -q "${TOMCAT_DOWNLOAD_URL}" -O "${TOMCAT_FILE}" || \
        error_exit "Failed to download Tomcat from ${TOMCAT_DOWNLOAD_URL}"
    
    log_msg "INFO" "Tomcat ${TOMCAT_VERSION} downloaded successfully"
}

###############################################################################
# Extract Tomcat
###############################################################################
extract_tomcat() {
    log_msg "INFO" "Extracting Tomcat to ${TOMCAT_HOME}..."
    
    # Remove existing installation if present
    if [[ -d "${TOMCAT_HOME}" ]]; then
        log_msg "WARN" "Existing Tomcat installation found, removing..."
        rm -rf "${TOMCAT_HOME}"
    fi
    
    mkdir -p "${TOMCAT_HOME}"
    tar -xf "/tmp/${TOMCAT_FILE}" -C "${TOMCAT_HOME}" --strip-components=1 || \
        error_exit "Failed to extract Tomcat archive"
    
    log_msg "INFO" "Tomcat extracted successfully"
}

###############################################################################
# Set directory permissions
###############################################################################
set_permissions() {
    log_msg "INFO" "Setting directory permissions..."
    
    chown -R tomcat:tomcat "${TOMCAT_HOME}" || \
        error_exit "Failed to set ownership on ${TOMCAT_HOME}"
    
    chmod -R 755 "${TOMCAT_HOME}" || \
        error_exit "Failed to set permissions on ${TOMCAT_HOME}"
    
    chmod +x "${TOMCAT_HOME}"/bin/*.sh || \
        error_exit "Failed to make startup scripts executable"
    
    log_msg "INFO" "Permissions set successfully"
}

###############################################################################
# Create systemd service file
###############################################################################
create_systemd_service() {
    log_msg "INFO" "Creating systemd service file..."
    
    cat > "/etc/systemd/system/${TOMCAT_DIR}.service" << EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat

Environment="JAVA_HOME=${JAVA_HOME}"
Environment="CATALINA_PID=${TOMCAT_HOME}/temp/tomcat.pid"
Environment="CATALINA_HOME=${TOMCAT_HOME}"
Environment="CATALINA_BASE=${TOMCAT_HOME}"

ExecStart=${TOMCAT_HOME}/bin/startup.sh
ExecStop=${TOMCAT_HOME}/bin/shutdown.sh

RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    log_msg "INFO" "Systemd service file created at /etc/systemd/system/${TOMCAT_DIR}.service"
}

###############################################################################
# Start and enable Tomcat service
###############################################################################
start_tomcat_service() {
    log_msg "INFO" "Reloading systemd daemon..."
    systemctl daemon-reload
    
    log_msg "INFO" "Starting Tomcat service..."
    systemctl start "${TOMCAT_DIR}" || \
        error_exit "Failed to start Tomcat service"
    
    log_msg "INFO" "Enabling Tomcat on boot..."
    systemctl enable "${TOMCAT_DIR}" || \
        error_exit "Failed to enable Tomcat service"
    
    log_msg "INFO" "Tomcat service started and enabled"
}

###############################################################################
# Cleanup temporary files
###############################################################################
cleanup() {
    log_msg "INFO" "Cleaning up temporary files..."
    rm -f "/tmp/${TOMCAT_FILE}"
    log_msg "INFO" "Cleanup completed"
}

###############################################################################
# Display installation summary
###############################################################################
print_summary() {
    local service_status
    service_status=$(systemctl is-active "${TOMCAT_DIR}" 2>/dev/null || echo "unknown")
    
    echo ""
    echo "============================================================================="
    echo "Apache Tomcat ${TOMCAT_VERSION} Installation Complete"
    echo "============================================================================="
    echo "Timestamp        : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Tomcat Version   : ${TOMCAT_VERSION}"
    echo "Tomcat Home      : ${TOMCAT_HOME}"
    echo "Service Name     : ${TOMCAT_DIR}"
    echo "Service Status   : ${service_status}"
    echo "Java Home        : ${JAVA_HOME}"
    echo "Log File         : $LOG_FILE"
    echo ""
    echo "USEFUL COMMANDS:"
    echo "  Start   : sudo systemctl start ${TOMCAT_DIR}"
    echo "  Stop    : sudo systemctl stop ${TOMCAT_DIR}"
    echo "  Restart : sudo systemctl restart ${TOMCAT_DIR}"
    echo "  Status  : sudo systemctl status ${TOMCAT_DIR}"
    echo "  Logs    : sudo journalctl -u ${TOMCAT_DIR} -f"
    echo ""
    echo "ACCESS URL: http://<server-ip>:8080"
    echo "============================================================================="
    
    log_msg "INFO" "Tomcat ${TOMCAT_VERSION} installation completed successfully"
}

###############################################################################
# Main execution
###############################################################################
main() {
    setup_logging
    check_prerequisites
    update_system
    create_tomcat_user
    download_tomcat
    extract_tomcat
    set_permissions
    create_systemd_service
    start_tomcat_service
    cleanup
    print_summary
}

# Run main function
main

exit 0