#!/bin/bash
###############################################################################
# Script Name  : 02_mysql84_secure_root.sh
# Description  : Secures MySQL 8.4 root account by changing the temporary
#                password and applying security hardening equivalent to
#                mysql_secure_installation. This includes removing anonymous
#                users, disabling remote root login, and removing test database.
# Usage        : sudo ./02_mysql84_secure_root.sh
# Prerequisites: - MySQL 8.4 installed and running (via 01_mysql84_install_al2023.sh)
#                - Temporary root password available in /var/log/mysqld.log
# Log Location : /var/log/mysql_install/mysql84_secure_root_<timestamp>.log
# Note         : Root password is entered interactively (not stored in script)
###############################################################################

set -e  # Exit immediately if any command fails

###############################################################################
# Variables
###############################################################################

# MySQL log file containing temporary password
MYSQL_LOG="/var/log/mysqld.log"

# Timeout configuration for waiting on temporary password
MAX_WAIT=60      # Maximum wait time in seconds
WAIT_INTERVAL=3  # Check interval in seconds

# Logging configuration
LOG_DIR="/var/log/mysql_install"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/mysql84_secure_root_${TIMESTAMP}.log"

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
    echo "MySQL 8.4 Root Security Configuration Log"
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
# Password validation function
# Validates password meets MySQL 8.4 policy requirements:
# - Minimum 8 characters
# - At least 1 uppercase letter (A-Z)
# - At least 1 lowercase letter (a-z)  
# - At least 1 digit (0-9)
# - At least 1 special character
###############################################################################
validate_password() {
    local password="$1"
    local errors=0

    # Check minimum length (8 characters)
    if [ ${#password} -lt 8 ]; then
        log_msg "ERROR" "Password must be at least 8 characters long."
        errors=$((errors + 1))
    fi

    # Check for uppercase letter
    if ! echo "$password" | grep -q '[A-Z]'; then
        log_msg "ERROR" "Password must contain at least one uppercase letter."
        errors=$((errors + 1))
    fi

    # Check for lowercase letter
    if ! echo "$password" | grep -q '[a-z]'; then
        log_msg "ERROR" "Password must contain at least one lowercase letter."
        errors=$((errors + 1))
    fi

    # Check for digit
    if ! echo "$password" | grep -q '[0-9]'; then
        log_msg "ERROR" "Password must contain at least one digit."
        errors=$((errors + 1))
    fi

    # Check for special character
    if ! echo "$password" | grep -q '[^a-zA-Z0-9]'; then
        log_msg "ERROR" "Password must contain at least one special character."
        errors=$((errors + 1))
    fi

    return $errors
}

###############################################################################
# Initialize logging
###############################################################################
setup_logging

log_msg "INFO" "Starting MySQL root account security configuration..."

###############################################################################
# Step 1: Validate MySQL service is running
###############################################################################
log_msg "INFO" "Step 1: Verifying MySQL service is running..."

if systemctl is-active --quiet mysqld; then
    log_msg "INFO" "MySQL service is running."
else
    log_msg "ERROR" "MySQL service is not running. Please start MySQL first."
    log_msg "ERROR" "Run: systemctl start mysqld"
    exit 1
fi

###############################################################################
# Step 2: Prompt for new root password interactively
# Uses read -s to hide password input from screen and logs
###############################################################################
log_msg "INFO" "Step 2: Prompting for new root password..."

echo ""
echo "============================================================================="
echo "MySQL 8.4 Password Policy Requirements:"
echo "  - Minimum 8 characters"
echo "  - At least 1 uppercase letter (A-Z)"
echo "  - At least 1 lowercase letter (a-z)"
echo "  - At least 1 digit (0-9)"
echo "  - At least 1 special character (!@#$%^&* etc.)"
echo "============================================================================="
echo ""

# Read password with confirmation
# Using /dev/tty to read directly from terminal (bypasses tee redirection)
echo -n "Enter new MySQL root password: "
read -s NEW_ROOT_PASSWORD < /dev/tty
echo ""

echo -n "Confirm new MySQL root password: "
read -s CONFIRM_PASSWORD < /dev/tty
echo ""

# Validate passwords match
if [ "$NEW_ROOT_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
    log_msg "ERROR" "Passwords do not match. Please run the script again."
    unset NEW_ROOT_PASSWORD CONFIRM_PASSWORD
    exit 1
fi

# Clear confirmation password from memory
unset CONFIRM_PASSWORD

log_msg "INFO" "Password input received."

###############################################################################
# Step 3: Validate new password meets MySQL 8.4 policy requirements
###############################################################################
log_msg "INFO" "Step 3: Validating password meets policy requirements..."

if validate_password "$NEW_ROOT_PASSWORD"; then
    log_msg "INFO" "Password validation passed."
else
    log_msg "ERROR" "Password validation failed. Please run the script again with a stronger password."
    unset NEW_ROOT_PASSWORD
    exit 1
fi

###############################################################################
# Step 4: Wait for and retrieve temporary root password from MySQL log
# MySQL generates the temporary password asynchronously after service start.
# This loop waits up to MAX_WAIT seconds for the password to appear.
###############################################################################
log_msg "INFO" "Step 4: Waiting for temporary root password in MySQL log..."

if [ ! -f "$MYSQL_LOG" ]; then
    log_msg "ERROR" "MySQL log file not found at: $MYSQL_LOG"
    unset NEW_ROOT_PASSWORD
    exit 1
fi

WAITED=0
echo -n "Waiting for temporary password to be generated"

while ! grep -q 'temporary password' "$MYSQL_LOG"; do
    # Check if timeout reached
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo ""
        log_msg "ERROR" "Timeout after ${MAX_WAIT}s waiting for temporary password."
        log_msg "ERROR" "The root password may have already been changed, or MySQL failed to start properly."
        log_msg "ERROR" "Check MySQL status: systemctl status mysqld"
        unset NEW_ROOT_PASSWORD
        exit 1
    fi
    
    # Print progress dot
    echo -n "."
    sleep $WAIT_INTERVAL
    WAITED=$((WAITED + WAIT_INTERVAL))
done

echo " Done!"

# Extract the temporary password (get the last occurrence in case of multiple restarts)
TEMP_ROOT_PASSWORD=$(grep 'temporary password' "$MYSQL_LOG" | tail -1 | awk '{print $NF}')

if [ -z "$TEMP_ROOT_PASSWORD" ]; then
    log_msg "ERROR" "Could not extract temporary root password from $MYSQL_LOG"
    unset NEW_ROOT_PASSWORD
    exit 1
fi

log_msg "INFO" "Temporary root password retrieved successfully."
# Note: Actual password is not logged for security

###############################################################################
# Step 5: Change root password
# Uses --connect-expired-password flag since temporary password is expired
###############################################################################
log_msg "INFO" "Step 5: Changing root password..."

mysql --connect-expired-password -u root -p"$TEMP_ROOT_PASSWORD" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$NEW_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF

if [ $? -eq 0 ]; then
    log_msg "INFO" "Root password changed successfully."
else
    log_msg "ERROR" "Failed to change root password."
    unset NEW_ROOT_PASSWORD TEMP_ROOT_PASSWORD
    exit 1
fi

# Clear temporary password from memory
unset TEMP_ROOT_PASSWORD

###############################################################################
# Step 6: Apply security hardening (equivalent to mysql_secure_installation)
###############################################################################
log_msg "INFO" "Step 6: Applying security hardening..."

mysql -u root -p"$NEW_ROOT_PASSWORD" <<EOF
-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Disallow remote root login (root can only connect from localhost)
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Remove test database if it exists
DROP DATABASE IF EXISTS test;

-- Remove privileges on test database
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Reload privilege tables
FLUSH PRIVILEGES;
EOF

if [ $? -eq 0 ]; then
    log_msg "INFO" "Security hardening applied successfully."
else
    log_msg "WARN" "Some security hardening steps may have failed."
fi

###############################################################################
# Step 7: Verify root login with new password
###############################################################################
log_msg "INFO" "Step 7: Verifying root login with new password..."

if mysql -u root -p"$NEW_ROOT_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; then
    log_msg "INFO" "Root login verification successful."
else
    log_msg "ERROR" "Root login verification failed."
    unset NEW_ROOT_PASSWORD
    exit 1
fi

###############################################################################
# Step 8: Display MySQL security status
###############################################################################
log_msg "INFO" "Step 8: Retrieving MySQL security status..."

echo ""
echo "--- MySQL User Accounts ---"
mysql -u root -p"$NEW_ROOT_PASSWORD" -e "SELECT User, Host, plugin FROM mysql.user;"

echo ""
echo "--- MySQL Databases ---"
mysql -u root -p"$NEW_ROOT_PASSWORD" -e "SHOW DATABASES;"

###############################################################################
# Display configuration summary
###############################################################################
echo ""
echo "============================================================================="
echo "MySQL Root Security Configuration Complete"
echo "============================================================================="
echo "Timestamp        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Service Status   : $(systemctl is-active mysqld)"
echo "Log File         : $LOG_FILE"
echo ""
echo "Security hardening applied:"
echo "  [✓] Root password changed"
echo "  [✓] Anonymous users removed"
echo "  [✓] Remote root login disabled"
echo "  [✓] Test database removed"
echo "  [✓] Privileges reloaded"
echo ""
echo "IMPORTANT: Store the root password securely!"
echo "           Consider using a password manager or secrets vault."
echo ""
echo "To test root login:"
echo "  mysql -u root -p"
echo ""
echo "NEXT STEP: Run the FinAlyzer configuration script"
echo "           ./03_mysql84_config_finalyzer.sh"
echo "============================================================================="

###############################################################################
# Security: Clear password variables from memory
###############################################################################
unset NEW_ROOT_PASSWORD

log_msg "INFO" "MySQL root security configuration completed successfully."

exit 0
