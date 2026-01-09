#!/bin/bash
###############################################################################
# Script Name  : install_tomcat10.sh
# Description  : Installs Apache Tomcat 10 on Amazon Linux / RHEL / CentOS
#                Creates tomcat user, configures systemd service, and
#                sets appropriate permissions.
#                Supports both dnf and yum package managers.
# Usage        : sudo ./install_tomcat10.sh
# Prerequisites: Root or sudo access, Java 21 installed
# Log Location : /var/log/tomcat10_install_<timestamp>.log
# Supported OS : Amazon Linux 2/2023, RHEL 7/8/9, CentOS 7/8, Rocky, AlmaLinux
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

# Java configuration
JAVA21_HOME="/usr/lib/jvm/java-21-amazon-corretto.x86_64"

# Logging configuration
LOG_DIR="/var/log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/tomcat10_install_${TIMESTAMP}.log"

# Package manager (will be detected)
PKG_MANAGER=""

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
# Detect operating system
###############################################################################
detect_os() {
    log_msg "INFO" "Detecting operating system..."
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        log_msg "INFO" "OS Detected: $NAME ($ID) version $VERSION_ID"
    else
        error_exit "Cannot detect operating system - /etc/os-release not found"
    fi
}

###############################################################################
# Detect package manager (dnf or yum)
###############################################################################
detect_package_manager() {
    log_msg "INFO" "Detecting package manager..."
    
    if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        log_msg "INFO" "Package manager detected: dnf"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        log_msg "INFO" "Package manager detected: yum"
    else
        error_exit "Neither dnf nor yum package manager found"
    fi
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
    log_msg "INFO" "Root access confirmed"
    
    # Check if Java 21 is installed
    if [[ ! -d "$JAVA21_HOME" ]]; then
        error_exit "Java 21 not found at $JAVA21_HOME. Please install Java 21 first using install_java21_corretto.sh"
    fi
    
    # Verify Java 21 binary
    if [[ ! -x "${JAVA21_HOME}/bin/java" ]]; then
        error_exit "Java 21 binary not executable at ${JAVA21_HOME}/bin/java"
    fi
    
    # Display Java version
    log_msg "INFO" "Java 21 found at: $JAVA21_HOME"
    log_msg "INFO" "Java version: $(${JAVA21_HOME}/bin/java -version 2>&1 | head -1)"
    
    log_msg "INFO" "Prerequisites check passed"
}

###############################################################################
# Update system packages
###############################################################################
update_system() {
    log_msg "INFO" "Updating system packages using $PKG_MANAGER..."
    
    case "$PKG_MANAGER" in
        dnf)
            dnf update -y || log_msg "WARN" "System update completed with warnings"
            ;;
        yum)
            yum update -y || log_msg "WARN" "System update completed with warnings"
            ;;
    esac
    
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
    log_msg "INFO" "Download URL: ${TOMCAT_DOWNLOAD_URL}"
    
    cd /tmp
    
    if [[ -f "${TOMCAT_FILE}" ]]; then
        log_msg "INFO" "Tomcat archive already exists in /tmp, removing old file..."
        rm -f "${TOMCAT_FILE}"
    fi
    
    wget -q "${TOMCAT_DOWNLOAD_URL}" -O "${TOMCAT_FILE}" || \
        error_exit "Failed to download Tomcat from ${TOMCAT_DOWNLOAD_URL}"
    
    # Verify download
    if [[ ! -s "${TOMCAT_FILE}" ]]; then
        error_exit "Downloaded file is empty or does not exist"
    fi
    
    log_msg "INFO" "Tomcat ${TOMCAT_VERSION} downloaded successfully ($(du -h ${TOMCAT_FILE} | cut -f1))"
}

###############################################################################
# Extract Tomcat
###############################################################################
extract_tomcat() {
    log_msg "INFO" "Extracting Tomcat to ${TOMCAT_HOME}..."
    
    # Remove existing installation if present
    if [[ -d "${TOMCAT_HOME}" ]]; then
        log_msg "WARN" "Removing existing Tomcat installation..."
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
# Configure system-wide CATALINA_HOME in /etc/profile.d
# FIXED VERSION - Ensures Tomcat 10 environment is set properly
###############################################################################
configure_system_tomcat_env() {
    log_msg "INFO" "Configuring system-wide Tomcat environment..."
    
    # Remove any old Tomcat environment files to avoid conflicts
    sudo rm -f /etc/profile.d/tomcat.sh
    sudo rm -f /etc/profile.d/tomcat9.sh
    
    sudo tee /etc/profile.d/tomcat10.sh > /dev/null << EOF
# Apache Tomcat 10 Environment
# Auto-generated by install_tomcat10.sh on $(date '+%Y-%m-%d %H:%M:%S')

# Remove any existing Tomcat paths from PATH to avoid conflicts
PATH=\$(echo "\$PATH" | sed -e 's|:/usr/share/tomcat[^:]*/bin||g' -e 's|/usr/share/tomcat[^:]*/bin:||g')

# Set Tomcat 10 environment
export CATALINA_HOME=${TOMCAT_HOME}
export CATALINA_BASE=${TOMCAT_HOME}
export PATH=\$CATALINA_HOME/bin:\$PATH
EOF
    
    # Make it executable
    sudo chmod +x /etc/profile.d/tomcat10.sh
    
    log_msg "INFO" "Created /etc/profile.d/tomcat10.sh with PATH cleanup"
}

###############################################################################
# Update user's .bashrc - Comment out old CATALINA_HOME settings
# Since we're using profile.d, we don't need to set it in .bashrc
###############################################################################
update_user_bashrc() {
    log_msg "INFO" "Updating user .bashrc files..."
    
    # Get list of home directories to update
    local homes_to_update=()
    
    # Add root's home
    homes_to_update+=("/root")
    
    # Find regular users with home directories (UID >= 1000)
    while IFS=: read -r username _ uid _ _ home _; do
        if [[ $uid -ge 1000 ]] && [[ -d "$home" ]]; then
            homes_to_update+=("$home")
        fi
    done < /etc/passwd
    
    for user_home in "${homes_to_update[@]}"; do
        local bashrc_file="${user_home}/.bashrc"
        
        if [[ ! -f "$bashrc_file" ]]; then
            log_msg "INFO" "No .bashrc found at $bashrc_file, skipping..."
            continue
        fi
        
        log_msg "INFO" "Processing $bashrc_file..."
        
        # Backup existing .bashrc
        cp "$bashrc_file" "${bashrc_file}.backup.$(date +%Y%m%d_%H%M%S)"
        log_msg "INFO" "Backup created: ${bashrc_file}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Comment out any existing CATALINA_HOME settings
        if grep -q "CATALINA_HOME" "$bashrc_file"; then
            log_msg "INFO" "Found CATALINA_HOME configuration in .bashrc, commenting out..."
            
            # Comment out all CATALINA_HOME and CATALINA_BASE lines
            sed -i 's|^export CATALINA_HOME=.*$|# [Managed by /etc/profile.d/tomcat10.sh] &|' "$bashrc_file"
            sed -i 's|^CATALINA_HOME=.*$|# [Managed by /etc/profile.d/tomcat10.sh] &|' "$bashrc_file"
            sed -i 's|^export CATALINA_BASE=.*$|# [Managed by /etc/profile.d/tomcat10.sh] &|' "$bashrc_file"
            sed -i 's|^CATALINA_BASE=.*$|# [Managed by /etc/profile.d/tomcat10.sh] &|' "$bashrc_file"
            
            # Also comment out PATH modifications for Tomcat
            sed -i 's|^export PATH=\$CATALINA_HOME/bin:\$PATH.*$|# [Managed by /etc/profile.d/tomcat10.sh] &|' "$bashrc_file"
            sed -i 's|^PATH=\$CATALINA_HOME/bin:\$PATH.*$|# [Managed by /etc/profile.d/tomcat10.sh] &|' "$bashrc_file"
            
            # Comment out combined PATH lines (with both JAVA_HOME and CATALINA_HOME)
            sed -i 's|^PATH=\$JAVA_HOME/bin:\$CATALINA_HOME/bin:\$PATH.*$|# [Managed by /etc/profile.d/tomcat10.sh] &|' "$bashrc_file"
            sed -i 's|^export PATH=\$JAVA_HOME/bin:\$CATALINA_HOME/bin:\$PATH.*$|# [Managed by /etc/profile.d/tomcat10.sh] &|' "$bashrc_file"
            
            log_msg "INFO" "Tomcat configuration commented out (now managed by /etc/profile.d/tomcat10.sh)"
        fi
        
        # Remove any old Tomcat blocks previously added by scripts
        if grep -q "# \[Tomcat" "$bashrc_file"; then
            log_msg "INFO" "Removing old Tomcat block..."
            sed -i '/# \[Tomcat/,/^export PATH=.*CATALINA_HOME.*$/d' "$bashrc_file"
        fi
        
        # Add a note that Tomcat is managed by profile.d
        if ! grep -q "Tomcat is managed by /etc/profile.d/tomcat10.sh" "$bashrc_file"; then
            cat >> "$bashrc_file" << 'EOF'

# Tomcat Environment
# Tomcat is managed by /etc/profile.d/tomcat10.sh for system-wide consistency
# To override, export CATALINA_HOME after this line
EOF
        fi
        
        log_msg "INFO" "Updated $bashrc_file - Tomcat now managed by /etc/profile.d/"
    done
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

Environment="JAVA_HOME=${JAVA21_HOME}"
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
    
    # Set permissions on service file
    chmod 644 "/etc/systemd/system/${TOMCAT_DIR}.service"
    
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
    
    # Wait for service to fully start
    sleep 3
    
    # Verify service is running
    if ! systemctl is-active "${TOMCAT_DIR}" &>/dev/null; then
        log_msg "ERROR" "Tomcat service failed to start. Checking logs..."
        journalctl -u "${TOMCAT_DIR}" --no-pager -n 20 || true
        error_exit "Tomcat service is not running"
    fi
    
    log_msg "INFO" "Tomcat service started and enabled successfully"
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
    echo ""
    echo "SYSTEM INFORMATION:"
    echo "  OS             : $NAME $VERSION_ID"
    echo "  Package Manager: $PKG_MANAGER"
    echo ""
    echo "TOMCAT CONFIGURATION:"
    echo "  Tomcat Version : ${TOMCAT_VERSION}"
    echo "  Tomcat Home    : ${TOMCAT_HOME}"
    echo "  Service Name   : ${TOMCAT_DIR}"
    echo "  Service Status : ${service_status}"
    echo "  Service File   : /etc/systemd/system/${TOMCAT_DIR}.service"
    echo ""
    echo "ENVIRONMENT CONFIGURATION:"
    echo "  System-wide    : /etc/profile.d/tomcat10.sh (PRIMARY - manages CATALINA_HOME)"
    echo "  User .bashrc   : Tomcat settings commented out (defers to profile.d)"
    echo "  CATALINA_HOME  : ${TOMCAT_HOME}"
    echo "  CATALINA_BASE  : ${TOMCAT_HOME}"
    echo ""
    echo "JAVA CONFIGURATION:"
    echo "  Java Home      : ${JAVA21_HOME}"
    echo "  Java Version   : $(${JAVA21_HOME}/bin/java -version 2>&1 | head -1)"
    echo ""
    echo "LOG FILE         : $LOG_FILE"
    echo ""
    echo "USEFUL COMMANDS:"
    echo "  Start   : sudo systemctl start ${TOMCAT_DIR}"
    echo "  Stop    : sudo systemctl stop ${TOMCAT_DIR}"
    echo "  Restart : sudo systemctl restart ${TOMCAT_DIR}"
    echo "  Status  : sudo systemctl status ${TOMCAT_DIR}"
    echo "  Logs    : sudo journalctl -u ${TOMCAT_DIR} -f"
    echo ""
    echo "IMPORTANT: To apply environment changes, you MUST:"
    echo "  Option 1: Log out and log back in (RECOMMENDED)"
    echo "  Option 2: Run: source /etc/profile.d/tomcat10.sh"
    echo ""
    echo "After applying changes, verify with:"
    echo "  echo \$CATALINA_HOME"
    echo "  which catalina.sh"
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
    detect_os
    detect_package_manager
    check_prerequisites
    update_system
    create_tomcat_user
    download_tomcat
    extract_tomcat
    set_permissions
    configure_system_tomcat_env
    update_user_bashrc
    create_systemd_service
    start_tomcat_service
    cleanup
    print_summary
}

# Run main function
main

exit 0