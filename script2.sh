#!/bin/bash
set -e

##############################################
# Script 3: FinAlyzer Database related Configuration
##############################################
echo "--- Configuring FinAlyzer Database Parameters ---"

CONFIG_PATH="/etc/my.cnf"
FINALYZER_CONFIG_PATH="/etc/my.cnf.finalyzer"
BACKUP_PATH="/etc/my.cnf.backup_$(date +%Y%m%d_%H%M%S)"

# 2a: Backup original my.cnf
echo "Step 1: Taking backup of my.cnf"
if [ -f "$CONFIG_PATH" ]; then
    echo "Backing up original configuration to $BACKUP_PATH"
    cp "$CONFIG_PATH" "$BACKUP_PATH"
else
    echo "Warning: Original $CONFIG_PATH not found. Proceeding without backup."
fi

# 2b: FinAlyzer configuration file must exist
echo "Step 2: Checking FinAlyzer configuration file"
if [ -f "$FINALYZER_CONFIG_PATH" ]; then
    echo "FinAlyzer configuration file found at $FINALYZER_CONFIG_PATH"
else
    echo "ERROR: FinAlyzer config file not found at $FINALYZER_CONFIG_PATH"
    echo "Please place my.cnf.finalyzer in /etc/"
    exit 1
fi

# 2c: Apply new config into my.cnf
echo "Step 3: Applying FinAlyzer configuration"
cp "$FINALYZER_CONFIG_PATH" "$CONFIG_PATH"
echo "FinAlyzer configuration applied successfully."

echo "--- FinAlyzer Database Configuration Completed ---"


echo "Starting MySQL..."
systemctl enable mysqld
systemctl start mysqld
