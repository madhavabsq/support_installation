#!/bin/bash
set -e

##############################################
# SCRIPT 1: Install MySQL and Secure Root Account
##############################################

##############################################
# Variables
##############################################
#NEW_ROOT_PASS="BSQadmin123#"             # Your desired root password
MYSQL_REPO="https://dev.mysql.com/get/mysql84-community-release-el9-2.noarch.rpm"
MYSQL_GPG_KEY="https://repo.mysql.com/RPM-GPG-KEY-mysql-2023"

echo "--- Creating FinAlyzer Temporary Directory (/findb/mysql_tmp) ---"
echo "Creating directory /findb/mysql_tmp and setting permissions..."

# Create directory recursively (-p)
mkdir -p /findb/mysql_tmp

# Set permissions
chmod 777 /findb/mysql_tmp

echo "Directory /findb/mysql_tmp created and permissions set."

echo "Downloading MySQL repo..."
wget -q "$MYSQL_REPO" -O /tmp/mysql-community-release.rpm

echo "Installing repo..."
if ! rpm -q mysql84-community-release > /dev/null; then
    rpm -Uvh /tmp/mysql-community-release.rpm
fi

# CRITICAL FIX: Manually force the repository to use RHEL 9 paths (el9) for AL2023
REPO_FILE="/etc/yum.repos.d/mysql-community.repo"
echo "Fixing MySQL repository path for Amazon Linux 2023..."
if [ -f "$REPO_FILE" ]; then
    sed -i 's/$releasever/9/g' "$REPO_FILE"
#    sed -i 's/el\/2023/el\/9/g' "$REPO_FILE"
fi

echo "Importing MySQL GPG key..."
wget -q "$MYSQL_GPG_KEY" -O /tmp/RPM-GPG-KEY-mysql
rpm --import /tmp/RPM-GPG-KEY-mysql

echo "Cleaning and preparing cache..."
dnf clean all
dnf makecache

echo "Installing MySQL packages..."
dnf install -y mysql-community-server mysql-community-client
