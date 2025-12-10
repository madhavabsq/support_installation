#!/bin/bash
set -e

##############################################
# Script 4: Secure MySQL (non-interactive)
##############################################
echo -n "Enter new MySQL root password: "
read -s NEW_ROOT_PASS
echo

echo "Waiting for MySQL temporary root password..."

MAX_WAIT=60  # max wait in seconds
WAITED=0
while ! grep -q 'temporary password' /var/log/mysqld.log; do
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo "Error: Timeout waiting for temporary password."
        exit 1
    fi
    echo -n "."
    sleep 3
    ((WAITED+=3))
done
echo

TEMP_PASS=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}' | tail -1)
echo "Temporary password obtained, securing MySQL root..."

# Try changing password with retry in case MySQL is not 100% ready
for i in {1..5}; do
    mysql --connect-expired-password -uroot -p"$TEMP_PASS" <<EOF && break
ALTER USER 'root'@'localhost' IDENTIFIED BY '$NEW_ROOT_PASS';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host!='localhost';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    echo "Attempt $i failed, retrying in 5 seconds..."
    sleep 5
done

if [ $? -ne 0 ]; then
    echo "Error: Failed to secure MySQL root account after multiple attempts."
    exit 2
fi

echo "MySQL root password set successfully."

##############################################
# Final Confirmation
##############################################
echo " "
echo " **SCRIPT 1 COMPLETE: MySQL Installed and Secured.**"
echo "The service is currently RUNNING with data at /var/lib/mysql."
echo "---------------------------------------------------------------------"

# MySQL Version Check
echo "MySQL Version Installed:"
mysql --version

echo "---------------------------------------------------------------------"
