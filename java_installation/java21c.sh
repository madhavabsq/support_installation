#!/bin/bash
###############################################################################
# Script       : install_java21_corretto.sh
# Description  : Install Amazon Corretto Java 21 on Amazon Linux / RHEL
#                Handles coexistence with existing Java 8 installation.
#                Updates alternatives and configures JAVA_HOME for Java 21.
# Usage        : sudo ./install_java21_corretto.sh
# Prerequisites: Root or sudo access, internet connectivity
# Log Location : /var/log/java21_install_<timestamp>.log
###############################################################################


set -euo pipefail

###############################################################################
# Configuration
###############################################################################
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/java21_install_$(date +%Y%m%d_%H%M%S).log"
REQUIRED_JAVA_VERSION="21"

# Java paths
JAVA8_HOME="/usr/lib/jvm/java-1.8.0-amazon-corretto.x86_64"
JAVA21_HOME="/usr/lib/jvm/java-21-amazon-corretto"

# Track Java 8 installation status
JAVA8_INSTALLED=false

###############################################################################
# Setup logging
# All output (stdout and stderr) will be sent to both console and log file
###############################################################################
setup_logging() {
    mkdir -p "$LOG_DIR" 2>/dev/null || {
        LOG_DIR="$HOME"
        LOG_FILE="${LOG_DIR}/java21_install_$(date +%Y%m%d_%H%M%S).log"
    }
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    
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
# Check for existing Java installations
###############################################################################
check_existing_java() {
    log_msg "INFO" "Checking for existing Java installations..."
    
    # Check for Java 8
    if [[ -d "$JAVA8_HOME" ]]; then
        log_msg "INFO" "Found existing Java 8 installation at: $JAVA8_HOME"
        JAVA8_INSTALLED=true
        "${JAVA8_HOME}/bin/java" -version 2>&1 | head -1 || true
    else
        log_msg "INFO" "Java 8 not found at $JAVA8_HOME"
        JAVA8_INSTALLED=false
    fi
    
    # Check for Java 21
    if [[ -d "$JAVA21_HOME" ]]; then
        log_msg "WARN" "Java 21 already installed at: $JAVA21_HOME"
        "${JAVA21_HOME}/bin/java" -version 2>&1 | head -1 || true
        echo ""
        read -p "Do you want to reinstall/reconfigure? (y/N): " REINSTALL || REINSTALL="n"
        if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
            log_msg "INFO" "Installation skipped by user"
            exit 0
        fi
        log_msg "INFO" "Proceeding with reinstallation/reconfiguration..."
    else
        log_msg "INFO" "Java 21 not currently installed"
    fi
    
    # Display current java version if available
    if command -v java &>/dev/null; then
        echo ""
        log_msg "INFO" "Current default Java version:"
        java -version 2>&1 | head -3
        echo ""
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
    log_msg "INFO" "Verifying Java 21 installation..."
    
    if [[ ! -d "$JAVA21_HOME" ]]; then
        error_exit "Java 21 directory not found at $JAVA21_HOME"
    fi
    
    if [[ ! -x "${JAVA21_HOME}/bin/java" ]]; then
        error_exit "Java 21 binary not executable at ${JAVA21_HOME}/bin/java"
    fi
    
    # Verify version
    if ! "${JAVA21_HOME}/bin/java" -version 2>&1 | grep -q "Corretto-21"; then
        error_exit "Java 21 verification failed - unexpected version"
    fi
    
    echo ""
    echo "Java 21 Version Information:"
    echo "----------------------------"
    "${JAVA21_HOME}/bin/java" -version
    echo ""
    
    log_msg "INFO" "Java 21 verification successful"
}

###############################################################################
# Configure system-wide JAVA_HOME in /etc/profile.d
###############################################################################
configure_system_java_home() {
    log_msg "INFO" "Configuring system-wide JAVA_HOME..."
    
    sudo tee /etc/profile.d/java21.sh > /dev/null << EOF
# Amazon Corretto Java 21 Environment
# Auto-generated by install_java21_corretto.sh on $(date '+%Y-%m-%d %H:%M:%S')
export JAVA_HOME=${JAVA21_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
    
    log_msg "INFO" "Created /etc/profile.d/java21.sh"
}

###############################################################################
# Update user's .bashrc with Java 21 configuration
# Handles existing Java 8 JAVA_HOME entries
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
        
        # Check if Java 8 JAVA_HOME exists and comment it out
        if grep -q "java-1.8.0-amazon-corretto" "$bashrc_file"; then
            log_msg "INFO" "Found Java 8 configuration, commenting out..."
            
            # Comment out Java 8 JAVA_HOME lines
            sed -i 's|^export JAVA_HOME=.*java-1.8.0-amazon-corretto.*$|# [Disabled by Java 21 installer] &|' "$bashrc_file"
            sed -i 's|^JAVA_HOME=.*java-1.8.0-amazon-corretto.*$|# [Disabled by Java 21 installer] &|' "$bashrc_file"
            
            log_msg "INFO" "Java 8 JAVA_HOME commented out (preserved for reference)"
        fi
        
        # Remove existing Java 21 block to avoid duplicates
        if grep -q "# \[Java Corretto 21\]" "$bashrc_file"; then
            log_msg "INFO" "Removing existing Java 21 block..."
            # Use a temporary file for safe editing
            grep -v "# \[Java Corretto 21\]" "$bashrc_file" | \
                grep -v "java-21-amazon-corretto" | \
                grep -v "# Added by install_java21_corretto.sh" > "${bashrc_file}.tmp" || true
            mv "${bashrc_file}.tmp" "$bashrc_file"
        fi
        
        # Append Java 21 configuration
        cat >> "$bashrc_file" << EOF

# [Java Corretto 21]
# Added by install_java21_corretto.sh on $(date '+%Y-%m-%d %H:%M:%S')
export JAVA_HOME=${JAVA21_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
        
        log_msg "INFO" "Updated $bashrc_file with Java 21 configuration"
    done
}

###############################################################################
# Update system alternatives (non-interactive)
###############################################################################
update_alternatives() {
    log_msg "INFO" "Configuring system alternatives for Java..."
    
    local java21_bin="${JAVA21_HOME}/bin/java"
    local javac21_bin="${JAVA21_HOME}/bin/javac"
    
    # Display available alternatives before update
    echo ""
    echo "Available Java Alternatives (before update):"
    echo "---------------------------------------------"
    sudo alternatives --display java 2>/dev/null | grep -E "^/|priority|current" | head -10 || echo "No alternatives configured"
    echo ""
    
    # Set Java 21 as the default
    if [[ -x "$java21_bin" ]]; then
        sudo alternatives --set java "$java21_bin" 2>/dev/null && \
            log_msg "INFO" "Set java alternative to: $java21_bin" || \
            log_msg "WARN" "Could not set java alternative automatically"
    fi
    
    if [[ -x "$javac21_bin" ]]; then
        sudo alternatives --set javac "$javac21_bin" 2>/dev/null && \
            log_msg "INFO" "Set javac alternative to: $javac21_bin" || \
            log_msg "WARN" "Could not set javac alternative automatically"
    fi
    
    # Display alternatives after update
    echo ""
    echo "Java Alternatives (after update):"
    echo "----------------------------------"
    sudo alternatives --display java 2>/dev/null | grep -E "^/|priority|current" | head -10 || true
    echo ""
    
    log_msg "INFO" "System alternatives configuration completed"
}

###############################################################################
# Display Java version switching instructions
###############################################################################
print_switching_instructions() {
    if [[ "$JAVA8_INSTALLED" == "true" ]]; then
        echo ""
        echo "============================================================================="
        echo "SWITCHING BETWEEN JAVA VERSIONS"
        echo "============================================================================="
        echo ""
        echo "Both Java 8 and Java 21 are installed. To switch between versions:"
        echo ""
        echo "Option 1: Use alternatives (system-wide, requires root)"
        echo "  Switch to Java 21: sudo alternatives --set java ${JAVA21_HOME}/bin/java"
        echo "  Switch to Java 8:  sudo alternatives --set java ${JAVA8_HOME}/bin/java"
        echo ""
        echo "Option 2: Override in current session"
        echo "  Use Java 21: export JAVA_HOME=${JAVA21_HOME} && export PATH=\$JAVA_HOME/bin:\$PATH"
        echo "  Use Java 8:  export JAVA_HOME=${JAVA8_HOME} && export PATH=\$JAVA_HOME/bin:\$PATH"
        echo ""
        echo "Option 3: Interactive selection"
        echo "  sudo alternatives --config java"
        echo "  sudo alternatives --config javac"
        echo ""
        echo "NOTE: To revert .bashrc to Java 8, restore from backup:"
        echo "  cp ~/.bashrc.backup.<timestamp> ~/.bashrc"
        echo ""
    fi
}

###############################################################################
# Print installation summary
###############################################################################
print_summary() {
    local current_java_link
    current_java_link=$(sudo alternatives --display java 2>/dev/null | grep 'link currently' | awk '{print $NF}' || echo 'N/A')
    
    echo ""
    echo "============================================================================="
    echo "Installation Completed Successfully!"
    echo "============================================================================="
    echo "Timestamp        : $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "INSTALLED JAVA VERSIONS:"
    if [[ "$JAVA8_INSTALLED" == "true" ]]; then
        echo "  Java 8         : $JAVA8_HOME"
    fi
    echo "  Java 21        : $JAVA21_HOME (DEFAULT)"
    echo ""
    echo "CONFIGURATION:"
    echo "  System-wide    : /etc/profile.d/java21.sh"
    echo "  User .bashrc   : Updated with Java 21 JAVA_HOME"
    echo "  Alternatives   : java and javac set to Java 21"
    echo ""
    echo "CURRENT DEFAULT:"
    echo "  JAVA_HOME      : $JAVA21_HOME"
    echo "  Java Binary    : $current_java_link"
    echo "  Java Version   : $(${JAVA21_HOME}/bin/java -version 2>&1 | head -n1)"
    echo ""
    echo "LOG FILE         : $LOG_FILE"
    echo "============================================================================="
    
    print_switching_instructions
    
    echo ""
    echo "IMPORTANT: To apply environment changes in current session:"
    echo "  source ~/.bashrc"
    echo "  OR"
    echo "  source /etc/profile.d/java21.sh"
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
    configure_system_java_home
    update_user_bashrc
    update_alternatives
    print_summary
}

# Run main function
main

exit 0