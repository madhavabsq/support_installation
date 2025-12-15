#!/bin/bash
###############################################################################
# Script Name  : 03_mysql84_config_finalyzer.sh
# Description  : Applies FinAlyzer-specific MySQL configuration by replacing
#                the default my.cnf with custom database parameters. Creates a
#                timestamped backup of the original configuration before
#                applying changes and restarts MySQL to apply new settings.
# Usage        : sudo ./03_mysql84_config_finalyzer.sh
# Prerequisites: - MySQL 8.4 installed (via 01_mysql84_install_al2023.sh)
#                - Root secured (via 02_mysql84_secure_root.sh)
#                - FinAlyzer config file at /etc/my.cnf.finalyzer
# Log Location : /var/log/mysql_install/mysql84_config_finalyzer_<timestamp>.log
###############################################################################

set -e  # Exit immediately if any command fails

###############################################################################
# Variables
###############################################################################
CONFIG_PATH="/etc/my.cnf"
FINALYZER_ROOTVOL_CONFIG_PATH="/etc/my.cnf.finalyzer"
BACKUP_PATH="/etc/my.cnf.backup_$(date +%Y%m%d_%H%M%S)"

# Timeout configuration for MySQL service restart
MAX_WAIT=30      # Maximum wait time in seconds
WAIT_INTERVAL=2  # Check interval in seconds

# Logging configuration
LOG_DIR="/var/log/mysql_install"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/mysql84_config_finalyzer_${TIMESTAMP}.log"

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
    echo "MySQL 8.4 FinAlyzer Configuration Log"
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

log_msg "INFO" "Starting FinAlyzer database configuration..."

###############################################################################
# Step 1: Backup original my.cnf
# Creates a timestamped backup to allow rollback if needed
###############################################################################
log_msg "INFO" "Step 1: Taking backup of my.cnf..."

if [ -f "$CONFIG_PATH" ]; then
    cp "$CONFIG_PATH" "$BACKUP_PATH"
    log_msg "INFO" "Backup created at: $BACKUP_PATH"
else
    log_msg "WARN" "Original $CONFIG_PATH not found. Proceeding without backup."
fi

###############################################################################
# Step 2: Verify FinAlyzer configuration file exists
# The custom config file must be pre-staged at /etc/my.cnf.finalyzer
###############################################################################
log_msg "INFO" "Step 2: Checking FinAlyzer configuration file..."

if [ -f "$FINALYZER_ROOTVOL_CONFIG_PATH" ]; then
    log_msg "INFO" "FinAlyzer configuration file found at: $FINALYZER_ROOTVOL_CONFIG_PATH"
else
    log_msg "ERROR" "FinAlyzer config file not found at: $FINALYZER_ROOTVOL_CONFIG_PATH"
    log_msg "ERROR" "Please place my.cnf.finalyzer in /etc/ before running this script."
    exit 1
fi

###############################################################################
# Step 3: Apply FinAlyzer configuration
# Replaces default my.cnf with FinAlyzer-optimized settings
###############################################################################
log_msg "INFO" "Step 3: Applying FinAlyzer configuration..."

cp "$FINALYZER_ROOTVOL_CONFIG_PATH" "$CONFIG_PATH"
log_msg "INFO" "FinAlyzer configuration applied successfully."

###############################################################################
# Step 4: Validate configuration syntax (optional but recommended)
# Checks for syntax errors before restarting MySQL
###############################################################################
log_msg "INFO" "Step 4: Validating MySQL configuration syntax..."

if mysqld --validate-config 2>/dev/null; then
    log_msg "INFO" "Configuration syntax validation passed."
else
    log_msg "WARN" "Configuration validation skipped or returned warnings."
    log_msg "WARN" "Proceeding with MySQL restart - check logs if issues occur."
fi

###############################################################################
# Step 5: Restart MySQL service to apply new configuration
# Uses restart instead of start since MySQL should already be running
###############################################################################
log_msg "INFO" "Step 5: Restarting MySQL to apply new configuration..."

systemctl enable mysqld
systemctl restart mysqld

# Wait for MySQL service to become active
WAITED=0
echo -n "Waiting for MySQL service to start"

while ! systemctl is-active --quiet mysqld; do
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo ""
        log_msg "ERROR" "Timeout after ${MAX_WAIT}s waiting for MySQL to start."
        log_msg "ERROR" "Check MySQL logs: journalctl -u mysqld -n 50"
        log_msg "ERROR" "To rollback: cp $BACKUP_PATH $CONFIG_PATH && systemctl restart mysqld"
        exit 1
    fi
    
    echo -n "."
    sleep $WAIT_INTERVAL
    WAITED=$((WAITED + WAIT_INTERVAL))
done

echo " Done!"
log_msg "INFO" "MySQL service restarted successfully."

###############################################################################
# Step 6: Verify MySQL is accepting connections
###############################################################################
log_msg "INFO" "Step 6: Verifying MySQL is accepting connections..."

if mysqladmin ping > /dev/null 2>&1; then
    log_msg "INFO" "MySQL is responding to ping."
else
    log_msg "WARN" "MySQL ping check failed. Service may still be initializing."
fi

###############################################################################
# Display configuration summary
###############################################################################
echo ""
echo "============================================================================="
echo "FinAlyzer Database Configuration Complete"
echo "============================================================================="
echo "Timestamp        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Config Source    : $FINALYZER_ROOTVOL_CONFIG_PATH"
echo "Config Applied   : $CONFIG_PATH"
echo "Backup Location  : $BACKUP_PATH"
echo "Service Status   : $(systemctl is-active mysqld)"
echo "Log File         : $LOG_FILE"
echo ""
echo "To verify configuration changes:"
echo "  mysql -u root -p -e \"SHOW VARIABLES LIKE '%buffer_pool%';\""
echo "  mysql -u root -p -e \"SHOW VARIABLES LIKE '%innodb%';\""
echo ""
echo "To rollback if needed:"
echo "  cp $BACKUP_PATH $CONFIG_PATH && systemctl restart mysqld"
echo "============================================================================="

log_msg "INFO" "FinAlyzer database configuration completed successfully."

exit 0
