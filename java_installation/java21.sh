#!/bin/bash
###############################################################################
# Script       : install_java21_corretto.sh
# Purpose      : Install Amazon Corretto Java 21 on Amazon Linux / RHEL
# Date         : 2025
###############################################################################
set -euo pipefail

###############################################################################
# Configuration
###############################################################################
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/java21_install_$(date +%Y%m%d_%H%M%S).log"
REQUIRED_JAVA_VERSION="21"

###############################################################################
# Setup logging
# All output (stdout and stderr) will be sent to both console and log file
###############################################################################
setup_logging() {
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR" 2>/dev/null || {
        # Fallback to home directory if /var/log is not writable
        LOG_DIR="$HOME"
        LOG_FILE="${LOG_DIR}/java21_install_$(date +%Y%m%d_%H%M%S).log"
    }
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    
    # Redirect stdout and stderr to tee, which writes to both console and log file
    exec > >(tee -a "$LOG_FILE") 2>&1
    
    echo "============================================================================="
    echo "Amazon Corretto Java 21 Installation Log"
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
# Check sudo access
###############################################################################
check_sudo() {
    log_msg "INFO" "Checking sudo privileges..."
    if ! sudo -v &>/dev/null; then
        error_exit "This script requires sudo privileges"
    fi
    log_msg "INFO" "Sudo access confirmed"
}

###############################################################################
# Detect operating system
###############################################################################
detect_os() {
    log_msg "INFO" "Detecting operating system..."
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        log_msg "INFO" "OS Detected: $NAME ($ID)"
    else
        error_exit "Cannot detect operating system - /etc/os-release not found"
    fi
}

###############################################################################
# Check for existing Java installation
###############################################################################
check_existing_java() {
    log_msg "INFO" "Checking for existing Java installation..."
    
    if command -v java &>/dev/null; then
        local current_version
        current_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 | cut -d'.' -f1)
        log_msg "INFO" "Found existing Java version: $current_version"
        
        if [[ "$current_version" == "$REQUIRED_JAVA_VERSION" ]]; then
            log_msg "WARN" "Java 21 is already installed"
            java -version
            echo ""
            read -p "Do you want to reinstall? (y/N): " REINSTALL
            if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
                log_msg "INFO" "Installation skipped by user"
                exit 0
            fi
            log_msg "INFO" "Proceeding with reinstallation..."
        fi
    else
        log_msg "INFO" "No existing Java installation found"
    fi
}

###############################################################################
# Configure repository (RHEL-based systems only)
###############################################################################
configure_repository() {
    log_msg "INFO" "Configuring package repository..."
    
    if [[ "$ID" == "rhel" || "$ID" == "centos" || "$ID" == "rocky" || "$ID" == "almalinux" ]]; then
        log_msg "INFO" "RHEL-compatible system detected - Adding Corretto repository"
        
        sudo rpm --import https://yum.corretto.aws/corretto.key || \
            error_exit "Failed to import Corretto GPG key"
        
        sudo curl -sLo /etc/yum.repos.d/amazon-corretto.repo https://yum.corretto.aws/corretto.repo || \
            error_exit "Failed to add Corretto repository"
        
        log_msg "INFO" "Corretto repository configured successfully"
    else
        log_msg "INFO" "Amazon Linux detected - Corretto repo already available"
    fi
}

###############################################################################
# Install Java 21
###############################################################################
install_java() {
    log_msg "INFO" "Installing Amazon Corretto Java 21..."
    
    sudo dnf install -y java-21-amazon-corretto-devel || \
        error_exit "Failed to install Java 21"
    
    log_msg "INFO" "Java 21 package installation completed"
}

###############################################################################
# Verify installation
###############################################################################
verify_installation() {
    log_msg "INFO" "Verifying Java installation..."
    
    if ! command -v java &>/dev/null; then
        error_exit "Java command not found after installation"
    fi
    
    if ! java -version 2>&1 | grep -q "Corretto-21"; then
        error_exit "Java 21 verification failed - unexpected version"
    fi
    
    echo ""
    echo "Java Version Information:"
    echo "-------------------------"
    java -version
    echo ""
    
    log_msg "INFO" "Java 21 verification successful"
}

###############################################################################
# Configure JAVA_HOME environment variable
###############################################################################
configure_java_home() {
    log_msg "INFO" "Configuring JAVA_HOME environment variable..."
    
    JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    
    if [[ ! -d "$JAVA_HOME" ]]; then
        error_exit "Invalid JAVA_HOME path: $JAVA_HOME"
    fi
    
    log_msg "INFO" "JAVA_HOME detected: $JAVA_HOME"
    
    # Create system-wide profile script
    sudo tee /etc/profile.d/java21.sh > /dev/null << EOF
# Amazon Corretto Java 21 Environment
# Auto-generated by install_java21_corretto.sh on $(date '+%Y-%m-%d %H:%M:%S')
export JAVA_HOME=${JAVA_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
    
    log_msg "INFO" "Created /etc/profile.d/java21.sh"
}

###############################################################################
# Update system alternatives (non-interactive)
###############################################################################
update_alternatives() {
    log_msg "INFO" "Updating system alternatives..."
    
    local java_bin="${JAVA_HOME}/bin/java"
    local javac_bin="${JAVA_HOME}/bin/javac"
    
    if [[ -x "$java_bin" ]]; then
        sudo alternatives --set java "$java_bin" 2>/dev/null && \
            log_msg "INFO" "Set java alternative to: $java_bin" || \
            log_msg "WARN" "Could not set java alternative (may be only version installed)"
    fi
    
    if [[ -x "$javac_bin" ]]; then
        sudo alternatives --set javac "$javac_bin" 2>/dev/null && \
            log_msg "INFO" "Set javac alternative to: $javac_bin" || \
            log_msg "WARN" "Could not set javac alternative (may be only version installed)"
    fi
    
    # Display current alternatives
    echo ""
    echo "Current Java Alternatives:"
    echo "--------------------------"
    sudo alternatives --display java 2>/dev/null | head -5 || true
    echo ""
}

###############################################################################
# Print installation summary
###############################################################################
print_summary() {
    echo ""
    echo "============================================================================="
    echo "Installation Completed Successfully!"
    echo "============================================================================="
    echo "JAVA_HOME       : $JAVA_HOME"
    echo "Java Binary     : $(which java)"
    echo "Java Version    : $(java -version 2>&1 | head -n1)"
    echo "Log File        : $LOG_FILE"
    echo "============================================================================="
    echo ""
    echo "IMPORTANT: To apply environment changes, either:"
    echo "  1. Start a new terminal session, OR"
    echo "  2. Run: source /etc/profile.d/java21.sh"
    echo ""
    echo "============================================================================="
    
    log_msg "INFO" "Installation completed successfully"
}

###############################################################################
# Main execution
###############################################################################
main() {
    setup_logging
    check_sudo
    detect_os
    check_existing_java
    configure_repository
    install_java
    verify_installation
    configure_java_home
    update_alternatives
    print_summary
}

# Run main function
main