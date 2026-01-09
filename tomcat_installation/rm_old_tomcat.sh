#!/bin/bash
set -e

# ===========================
# CONFIGURABLE VARIABLES
# ===========================
TOMCAT_VERSION="10.1.49"
TOMCAT_FILE="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_DIR="tomcat10"
TOMCAT_HOME="/usr/share/${TOMCAT_DIR}"
BACKUP_DIR="/home/ec2-user"
JAVA_HOME="/usr/lib/jvm/java-21-amazon-corretto"


#echo "----------------------------------------------------"
#echo " STEP 0: Updating System Packages"
#echo "----------------------------------------------------"
#sudo dnf update -y

# =====================================================
# STEP 0.1: Backup existing Tomcat directories (IF ANY)
# =====================================================
echo "----------------------------------------------------"
echo " Checking existing Tomcat directories"
echo "----------------------------------------------------"

if ls /usr/share/tomcat* &>/dev/null; then
  for dir in /usr/share/tomcat*; do
    if [ -d "$dir" ] && [ "$dir" != "$TOMCAT_HOME" ]; then
      echo "Found existing Tomcat directory: $dir"
      sudo mv "$dir" "${BACKUP_DIR}/$(basename "$dir")_$(date +%F_%H-%M-%S)"
      echo "Backed up to ${BACKUP_DIR}"
    fi
  done
else
  echo "No existing Tomcat directories found. Skipping backup."
fi

# =====================================================
# STEP 0.2: Stop & remove old Tomcat services (IF ANY)
# =====================================================
echo "----------------------------------------------------"
echo " Checking existing Tomcat systemd services"
echo "----------------------------------------------------"

if ls /etc/systemd/system/tomcat*.service &>/dev/null; then
  for svc in /etc/systemd/system/tomcat*.service; do
    if [ -f "$svc" ] && [[ "$(basename "$svc")" != "${TOMCAT_DIR}.service" ]]; then
      SERVICE_NAME=$(basename "$svc" .service)
      echo "Found service: $SERVICE_NAME"

      sudo systemctl stop "$SERVICE_NAME" || true
      sudo systemctl disable "$SERVICE_NAME" || true
      sudo rm -f "$svc"

      echo "Removed service: $SERVICE_NAME"
    fi
  done
else
  echo "No existing Tomcat services found. Skipping cleanup."
fi

sudo systemctl daemon-reload