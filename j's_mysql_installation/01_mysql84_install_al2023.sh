#!/bin/bash
###############################################################################
# Script Name  : 01_mysql84_install_al2023.sh
# Description  : Installs MySQL 8.4 Community Server on Amazon Linux 2023
#                This script handles the compatibility workaround required
#                for AL2023 by forcing RHEL 9 (el9) repository paths.
# Usage        : sudo ./01_mysql84_install_al2023.sh
# Prerequisites: Root or sudo access, internet connectivity
# Log Location : /var/log/mysql_install/mysql84_install_<timestamp>.log
# Note         : Root account security configuration is handled separately
#                in 02_mysql84_secure_root.sh
###############################################################################

set -e  # Exit immediately if any command fails

###############################################################################
# Variables
###############################################################################
MYSQL_REPO_URL="https://dev.mysql.com/get/mysql84-community-release-el9-2.noarch.rpm"
MYSQL_GPG_KEY_URL="https://repo.mysql.com/RPM-GPG-KEY-mysql-2023"
MYSQL_REPO_FILE="/etc/yum.repos.d/mysql-community.repo"
MYSQL_TMP_DIR="/findb/mysql_tmp"

# Logging configuration
LOG_DIR="/var/log/mysql_install"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/mysql84_install_${TIMESTAMP}.log"

###############################################################################
# Setup logging
# All output (stdout and stderr) will be sent to both console and log file
###############################################################################
setup_logging() {
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    
    # Redirect stdout and stderr to tee, which writes to both console and log file
    exec > >(tee -a "$LOG_FILE") 2>&1
    
    echo "============================================================================="
    echo "MySQL 8.4 Installation Log"
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
# Initialize logging
###############################################################################
setup_logging

###############################################################################
# Create MySQL temporary directory
###############################################################################
log_msg "INFO" "Creating MySQL temporary directory..."
mkdir -p "$MYSQL_TMP_DIR"
chown mysql:mysql "$MYSQL_TMP_DIR" 2>/dev/null || log_msg "NOTE" "mysql user doesn't exist yet, will set ownership after install"
chmod 750 "$MYSQL_TMP_DIR"
log_msg "INFO" "Directory $MYSQL_TMP_DIR created and permissions set."

###############################################################################
# Download and install MySQL repository
###############################################################################
log_msg "INFO" "Downloading MySQL Community repository package..."
wget -q "$MYSQL_REPO_URL" -O /tmp/mysql-community-release.rpm

log_msg "INFO" "Installing MySQL repository..."
if ! rpm -q mysql84-community-release > /dev/null 2>&1; then
    rpm -Uvh /tmp/mysql-community-release.rpm
else
    log_msg "INFO" "MySQL repository already installed, skipping..."
fi

###############################################################################
# Fix repository paths for Amazon Linux 2023 compatibility
# AL2023 is not directly supported by MySQL repos, but RHEL 9 packages
# are compatible. This replaces $releasever with hardcoded '9'.
###############################################################################
log_msg "INFO" "Applying Amazon Linux 2023 compatibility fix for MySQL repository..."
if [ -f "$MYSQL_REPO_FILE" ]; then
    sed -i 's/$releasever/9/g' "$MYSQL_REPO_FILE"
    log_msg "INFO" "Repository path updated to use RHEL 9 packages."
else
    log_msg "ERROR" "MySQL repository file not found at $MYSQL_REPO_FILE"
    exit 1
fi

###############################################################################
# Import MySQL GPG key for package verification
###############################################################################
log_msg "INFO" "Downloading and importing MySQL GPG key..."
wget -q "$MYSQL_GPG_KEY_URL" -O /tmp/RPM-GPG-KEY-mysql
rpm --import /tmp/RPM-GPG-KEY-mysql
log_msg "INFO" "GPG key imported successfully."

###############################################################################
# Refresh DNF cache and install MySQL packages
###############################################################################
log_msg "INFO" "Cleaning DNF cache and rebuilding..."
dnf clean all
dnf makecache

log_msg "INFO" "Installing MySQL Community Server and Client..."
dnf install -y mysql-community-server mysql-community-client

###############################################################################
# Fix ownership of MySQL temp directory (now that mysql user exists)
###############################################################################
log_msg "INFO" "Setting ownership on MySQL temporary directory..."
chown mysql:mysql "$MYSQL_TMP_DIR"

###############################################################################
# Start and enable MySQL service
###############################################################################
log_msg "INFO" "Starting MySQL service..."
systemctl start mysqld
systemctl enable mysqld

###############################################################################
# Display installation summary
###############################################################################
echo ""
echo "============================================================================="
echo "MySQL 8.4 Installation Complete"
echo "============================================================================="
echo "Timestamp        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "MySQL Version    : $(mysql --version)"
echo "Service Status   : $(systemctl is-active mysqld)"
echo "Temp Directory   : $MYSQL_TMP_DIR"
echo "Log File         : $LOG_FILE"
echo ""
echo "NEXT STEP: Run the root security script to set the root password"
echo "           Temporary root password is in: /var/log/mysqld.log"
echo "           Command: grep 'temporary password' /var/log/mysqld.log"
echo "============================================================================="

###############################################################################
# Cleanup temporary files
###############################################################################
log_msg "INFO" "Cleaning up temporary files..."
rm -f /tmp/mysql-community-release.rpm /tmp/RPM-GPG-KEY-mysql

log_msg "INFO" "MySQL 8.4 installation completed successfully."

exit 0
