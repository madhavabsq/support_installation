#!/bin/bash
###############################################################################
# Script Name  : 04_mysql84_migrate_datadir.sh
# Description  : Migrates MySQL data directory from default location
#                (/var/lib/mysql) to a dedicated mount point (/findb/mysql).
#                This allows placing MySQL data on a separate EBS volume for
#                better performance, scalability, and backup management.
#                Also disables SELinux and applies final my.cnf configuration.
# Usage        : sudo ./04_mysql84_migrate_datadir.sh
# Prerequisites: - MySQL 8.4 installed and configured (Scripts 01-03 completed)
#                - /findb mount point exists and is mounted
#                - Final config file at /etc/my.cnf.finalyzer-mountpoint
# Log Location : /var/log/mysql_install/mysql84_migrate_datadir_<timestamp>.log
# WARNING      : This script stops MySQL during migration. Plan for downtime.
###############################################################################

set -e  # Exit immediately if any command fails

###############################################################################
# Variables
###############################################################################
OLD_DATADIR="/var/lib/mysql"
NEW_DATADIR="/findb/mysql"
MYSQL_TMP_DIR="/findb/mysql_tmp"
FINALYZER_MOUNTPOINT_CONFIG_PATH="/etc/my.cnf.finalyzer-mountpoint"
ACTIVE_CONFIG="/etc/my.cnf"
SELINUX_CONFIG="/etc/selinux/config"

# Timeout configuration for MySQL service operations
MAX_WAIT=60      # Maximum wait time in seconds
WAIT_INTERVAL=3  # Check interval in seconds

# Logging configuration
LOG_DIR="/var/log/mysql_install"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/mysql84_migrate_datadir_${TIMESTAMP}.log"

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
    echo "MySQL 8.4 Data Directory Migration Log"
    echo "============================================================================="
    echo "Timestamp       : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Hostname        : $(hostname)"
    echo "OS Version      : $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "Log File        : $LOG_FILE"
    echo "Old Datadir     : $OLD_DATADIR"
    echo "New Datadir     : $NEW_DATADIR"
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

log_msg "INFO" "Starting MySQL data directory migration..."

###############################################################################
# Pre-flight checks
###############################################################################
log_msg "INFO" "Running pre-flight checks..."

# Check if /findb mount point exists
if [ ! -d "/findb" ]; then
    log_msg "ERROR" "/findb directory does not exist."
    log_msg "ERROR" "Please create and mount the dedicated volume first."
    exit 1
fi

# Check if /findb is a mount point (not just a directory on root)
if mountpoint -q /findb; then
    log_msg "INFO" "/findb is a valid mount point."
    df -h /findb
else
    log_msg "WARN" "/findb is not a separate mount point."
    log_msg "WARN" "Proceeding, but recommend using a dedicated volume for production."
fi

# Check if final config file exists
if [ ! -f "$FINALYZER_MOUNTPOINT_CONFIG_PATH" ]; then
    log_msg "ERROR" "Final configuration file not found: $FINALYZER_MOUNTPOINT_CONFIG_PATH"
    log_msg "ERROR" "Please place my.cnf.finalyzer.final in /etc/ before running."
    exit 1
fi

# Check if old datadir exists
if [ ! -d "$OLD_DATADIR" ]; then
    log_msg "ERROR" "Source data directory not found: $OLD_DATADIR"
    exit 1
fi

log_msg "INFO" "Pre-flight checks passed."

###############################################################################
# Step 1: Create MySQL temporary directory on new mount
###############################################################################
log_msg "INFO" "Step 1: Creating MySQL temporary directory..."

if [ ! -d "$MYSQL_TMP_DIR" ]; then
    mkdir -p "$MYSQL_TMP_DIR"
    log_msg "INFO" "Created directory: $MYSQL_TMP_DIR"
else
    log_msg "INFO" "Directory already exists: $MYSQL_TMP_DIR"
fi

chown mysql:mysql "$MYSQL_TMP_DIR"
chmod 755 "$MYSQL_TMP_DIR"
log_msg "INFO" "Permissions set on $MYSQL_TMP_DIR (mysql:mysql, 755)"

###############################################################################
# Step 2: Stop MySQL service
# MySQL must be stopped before copying data directory to ensure consistency
###############################################################################
log_msg "INFO" "Step 2: Stopping MySQL service..."

if systemctl is-active --quiet mysqld; then
    systemctl stop mysqld
    
    # Wait for MySQL to fully stop
    WAITED=0
    echo -n "Waiting for MySQL to stop"
    
    while systemctl is-active --quiet mysqld; do
        if [ $WAITED -ge $MAX_WAIT ]; then
            echo ""
            log_msg "ERROR" "Timeout waiting for MySQL to stop."
            exit 1
        fi
        echo -n "."
        sleep $WAIT_INTERVAL
        WAITED=$((WAITED + WAIT_INTERVAL))
    done
    
    echo " Done!"
    log_msg "INFO" "MySQL service stopped successfully."
else
    log_msg "INFO" "MySQL service is already stopped."
fi

###############################################################################
# Step 3: Disable SELinux (if applicable)
# SELinux can block MySQL from accessing non-default data directories.
# On Amazon Linux 2023, SELinux is typically not enforcing.
###############################################################################
log_msg "INFO" "Step 3: Configuring SELinux..."

if [ -f "$SELINUX_CONFIG" ]; then
    # Check current SELinux status
    CURRENT_SELINUX=$(grep "^SELINUX=" "$SELINUX_CONFIG" | cut -d'=' -f2)
    log_msg "INFO" "Current SELinux setting: $CURRENT_SELINUX"
    
    if [ "$CURRENT_SELINUX" != "disabled" ]; then
        sed -i 's/^SELINUX=.*/SELINUX=disabled/g' "$SELINUX_CONFIG"
        log_msg "INFO" "SELinux set to disabled in $SELINUX_CONFIG"
        log_msg "WARN" "A system reboot is required for SELinux changes to take full effect."
    else
        log_msg "INFO" "SELinux is already disabled."
    fi
else
    log_msg "INFO" "SELinux config not found - likely not installed (normal for AL2023)."
fi

# Attempt to set permissive mode immediately (may fail if SELinux not installed)
if command -v setenforce &> /dev/null; then
    setenforce 0 2>/dev/null || log_msg "INFO" "setenforce skipped (SELinux not enforcing)."
else
    log_msg "INFO" "setenforce command not available."
fi

###############################################################################
# Step 4: Copy MySQL data directory to /findb
# Uses cp -R -p to preserve permissions, ownership, and timestamps
###############################################################################
log_msg "INFO" "Step 4: Copying MySQL data directory to new location..."

# Check if destination already has data
if [ -d "$NEW_DATADIR" ] && [ "$(ls -A $NEW_DATADIR 2>/dev/null)" ]; then
    log_msg "WARN" "Destination directory $NEW_DATADIR already contains data!"
    log_msg "WARN" "Creating backup of existing destination..."
    mv "$NEW_DATADIR" "${NEW_DATADIR}.backup_${TIMESTAMP}"
    log_msg "INFO" "Existing data moved to: ${NEW_DATADIR}.backup_${TIMESTAMP}"
fi

# Calculate source size for progress indication
SOURCE_SIZE=$(du -sh "$OLD_DATADIR" 2>/dev/null | cut -f1)
log_msg "INFO" "Source data size: $SOURCE_SIZE"
log_msg "INFO" "Copying from $OLD_DATADIR to $NEW_DATADIR ..."
log_msg "INFO" "This may take several minutes depending on data size..."

# Copy with preserved attributes
cp -R -p "$OLD_DATADIR" "$NEW_DATADIR"

if [ $? -eq 0 ]; then
    log_msg "INFO" "Data copy completed successfully."
else
    log_msg "ERROR" "Data copy failed!"
    exit 1
fi

# Verify ownership and set if needed
log_msg "INFO" "Verifying ownership on $NEW_DATADIR ..."
chown -R mysql:mysql "$NEW_DATADIR"
log_msg "INFO" "Ownership set to mysql:mysql"

# Display directory contents for verification
log_msg "INFO" "Verifying /findb contents:"
echo ""
echo "--- /findb directory listing ---"
ls -ld /findb
ls -l /findb
echo ""

# Compare source and destination sizes
DEST_SIZE=$(du -sh "$NEW_DATADIR" 2>/dev/null | cut -f1)
log_msg "INFO" "Source size: $SOURCE_SIZE | Destination size: $DEST_SIZE"

###############################################################################
# Step 5: Apply final my.cnf configuration
# This config file should have datadir=/findb/mysql and other final settings
###############################################################################
log_msg "INFO" "Step 5: Applying final my.cnf configuration..."

# Backup current config before replacing
BACKUP_CONFIG="/etc/my.cnf.backup_before_migration_${TIMESTAMP}"
cp "$ACTIVE_CONFIG" "$BACKUP_CONFIG"
log_msg "INFO" "Current config backed up to: $BACKUP_CONFIG"

# Apply final configuration
cp "$FINALYZER_MOUNTPOINT_CONFIG_PATH" "$ACTIVE_CONFIG"
log_msg "INFO" "Final configuration applied from: $FINALYZER_MOUNTPOINT_CONFIG_PATH"

# Verify datadir setting in new config
if grep -q "datadir.*=.*/findb/mysql" "$ACTIVE_CONFIG"; then
    log_msg "INFO" "Verified: datadir is set to /findb/mysql in my.cnf"
else
    log_msg "WARN" "Could not verify datadir setting in my.cnf"
    log_msg "WARN" "Please ensure datadir=/findb/mysql is set correctly"
fi

###############################################################################
# Step 6: Start MySQL service with new configuration
###############################################################################
log_msg "INFO" "Step 6: Starting MySQL service..."

systemctl start mysqld

# Wait for MySQL to start
WAITED=0
echo -n "Waiting for MySQL to start"

while ! systemctl is-active --quiet mysqld; do
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo ""
        log_msg "ERROR" "Timeout waiting for MySQL to start."
        log_msg "ERROR" "Check MySQL logs: journalctl -u mysqld -n 100"
        log_msg "ERROR" "Check error log: tail -100 /var/log/mysqld.log"
        log_msg "INFO" "To rollback: cp $BACKUP_CONFIG $ACTIVE_CONFIG && systemctl start mysqld"
        exit 1
    fi
    echo -n "."
    sleep $WAIT_INTERVAL
    WAITED=$((WAITED + WAIT_INTERVAL))
done

echo " Done!"
log_msg "INFO" "MySQL service started successfully."

# Enable MySQL to start on boot
systemctl enable mysqld
log_msg "INFO" "MySQL enabled for automatic start on boot."

###############################################################################
# Step 7: Verify new datadir is in use
###############################################################################
log_msg "INFO" "Step 7: Verifying MySQL is using new data directory..."

echo ""
echo "============================================================================="
echo "Please enter MySQL root password to verify datadir configuration:"
echo "============================================================================="

# Verify datadir
CURRENT_DATADIR=$(mysql -u root -p -N -e "SELECT @@datadir;" 2>/dev/null) || true

if [ -n "$CURRENT_DATADIR" ]; then
    log_msg "INFO" "MySQL datadir verification: $CURRENT_DATADIR"
    
    if [[ "$CURRENT_DATADIR" == *"/findb/mysql"* ]]; then
        log_msg "INFO" "SUCCESS: MySQL is using the new data directory!"
    else
        log_msg "WARN" "MySQL datadir does not match expected path."
        log_msg "WARN" "Expected: /findb/mysql/ | Actual: $CURRENT_DATADIR"
    fi
else
    log_msg "WARN" "Could not verify datadir (password may have been skipped)."
    log_msg "INFO" "Manual verification: mysql -u root -p -e \"SELECT @@datadir;\""
fi

###############################################################################
# Step 8: Display migration summary
###############################################################################
echo ""
echo "============================================================================="
echo "MySQL Data Directory Migration Complete"
echo "============================================================================="
echo "Timestamp        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Old Datadir      : $OLD_DATADIR"
echo "New Datadir      : $NEW_DATADIR"
echo "Tmp Directory    : $MYSQL_TMP_DIR"
echo "Config Backup    : $BACKUP_CONFIG"
echo "Service Status   : $(systemctl is-active mysqld)"
echo "Log File         : $LOG_FILE"
echo ""
echo "Migration steps completed:"
echo "  [✓] MySQL temporary directory created"
echo "  [✓] MySQL service stopped"
echo "  [✓] SELinux configured"
echo "  [✓] Data directory copied to /findb/mysql"
echo "  [✓] Final my.cnf configuration applied"
echo "  [✓] MySQL service started"
echo ""
echo "Post-migration recommendations:"
echo "  1. Verify application connectivity"
echo "  2. Run: mysql -u root -p -e \"SELECT @@datadir;\""
echo "  3. After confirming everything works, consider removing old datadir:"
echo "     rm -rf $OLD_DATADIR (ONLY after thorough testing!)"
echo ""
echo "To rollback if needed:"
echo "  systemctl stop mysqld"
echo "  cp $BACKUP_CONFIG $ACTIVE_CONFIG"
echo "  systemctl start mysqld"
echo "============================================================================="

log_msg "INFO" "MySQL data directory migration completed successfully."

exit 0
