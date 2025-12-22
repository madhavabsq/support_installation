"""
Yes, backup / stop / remove logic must run ONLY IF Tomcat already exists.
If no Tomcat is present, the script should skip those steps silently and continue.

Good news: we can make this very clean and safe using proper if conditions.

Below is the corrected and hardened version of the logic, followed by the full final script.
"""
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

echo "----------------------------------------------------"
echo " STEP 0: Updating System Packages"
echo "----------------------------------------------------"
sudo dnf update -y

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

# =====================================================
# STEP 1: Create tomcat user & group
# =====================================================
echo "----------------------------------------"
echo " STEP 1: Create tomcat user & group"
echo "----------------------------------------"

sudo groupadd tomcat || true
sudo useradd -M -s /usr/sbin/nologin -g tomcat -d ${TOMCAT_HOME} tomcat || true

# =====================================================
# STEP 2: Download Tomcat
# =====================================================
echo "----------------------------------------"
echo " STEP 2: Download Tomcat ${TOMCAT_VERSION}"
echo "----------------------------------------"

cd /tmp
rm -f ${TOMCAT_FILE}
wget https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/${TOMCAT_FILE}

# =====================================================
# STEP 3: Extract Tomcat
# =====================================================
echo "----------------------------------------"
echo " STEP 3: Extract Tomcat"
echo "----------------------------------------"

sudo mkdir -p ${TOMCAT_HOME}
sudo tar -xvf ${TOMCAT_FILE} -C ${TOMCAT_HOME} --strip-components=1

# =====================================================
# STEP 4: Permissions
# =====================================================
echo "----------------------------------------"
echo " STEP 4: Set permissions"
echo "----------------------------------------"

sudo chown -R tomcat:tomcat ${TOMCAT_HOME}
sudo chmod -R 755 ${TOMCAT_HOME}
sudo chmod +x ${TOMCAT_HOME}/bin/*.sh

# =====================================================
# STEP 5: Create systemd service
# =====================================================
echo "----------------------------------------"
echo " Creating Tomcat systemd service"
echo "----------------------------------------"

sudo bash -c "cat > /etc/systemd/system/${TOMCAT_DIR}.service <<EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment=JAVA_HOME=${JAVA_HOME}
Environment=CATALINA_PID=${TOMCAT_HOME}/temp/tomcat.pid
Environment=CATALINA_HOME=${TOMCAT_HOME}
Environment=CATALINA_BASE=${TOMCAT_HOME}
ExecStart=${TOMCAT_HOME}/bin/startup.sh
ExecStop=${TOMCAT_HOME}/bin/shutdown.sh
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

# Explicit executable permission (as requested)
sudo chmod +x /etc/systemd/system/${TOMCAT_DIR}.service

# =====================================================
# STEP 6: Start & enable Tomcat
# =====================================================
echo "----------------------------------------"
echo " Reloading systemd & starting Tomcat"
echo "----------------------------------------"

sudo systemctl daemon-reload
sudo systemctl start ${TOMCAT_DIR}
sudo systemctl enable ${TOMCAT_DIR}

# =====================================================
# STEP 7: Status
# =====================================================
echo "----------------------------------------"
echo " Tomcat Status"
echo "----------------------------------------"

sudo systemctl status ${TOMCAT_DIR} --no-pager
