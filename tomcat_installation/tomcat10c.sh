#!/bin/bash
set -e  # Exit if any command fails

# ===========================
# CONFIGURABLE VARIABLES
# ===========================
TOMCAT_VERSION="10.1.49"
TOMCAT_FILE="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_DIR="tomcat10"            # <---- Change folder name here only
TOMCAT_HOME="/usr/share/${TOMCAT_DIR}"

echo "----------------------------------------------------"
echo " STEP 0: Updating System Packages"
echo "----------------------------------------------------"
sudo dnf update -y

echo "----------------------------------------"
echo "  STEP 1: Create tomcat group & user"
echo "----------------------------------------"

sudo groupadd tomcat || true
sudo useradd -M -s /usr/sbin/nologin -g tomcat -d ${TOMCAT_HOME} tomcat || true

echo "Tomcat user & group created."

echo "----------------------------------------"
echo "  STEP 2: Download Apache Tomcat ${TOMCAT_VERSION}"
echo "----------------------------------------"

cd /tmp
wget https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/${TOMCAT_FILE}

echo "Downloaded Tomcat ${TOMCAT_VERSION}"

echo "----------------------------------------"
echo "  STEP 3: Extract Tomcat into ${TOMCAT_HOME}"
echo "----------------------------------------"

sudo mkdir -p ${TOMCAT_HOME}
sudo tar -xvf ${TOMCAT_FILE} -C ${TOMCAT_HOME} --strip-components=1

echo "Tomcat extracted."

echo "----------------------------------------"
echo "  STEP 4: Set directory permissions"
echo "----------------------------------------"

sudo chown -R tomcat:tomcat ${TOMCAT_HOME}
sudo chmod -R 755 ${TOMCAT_HOME}

echo "Permissions set."

echo "----------------------------------------"
echo "  STEP 5: Make startup scripts executable"
echo "----------------------------------------"

sudo chmod +x ${TOMCAT_HOME}/bin/*.sh

echo "Tomcat installation setup complete!"

echo "----------------------------------------"
echo "  Creating Tomcat systemd service file"
echo "----------------------------------------"

sudo bash -c "cat > /etc/systemd/system/${TOMCAT_DIR}.service <<EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment=\"JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto\"
Environment=\"CATALINA_PID=${TOMCAT_HOME}/temp/tomcat.pid\"
Environment=\"CATALINA_HOME=${TOMCAT_HOME}\"
Environment=\"CATALINA_BASE=${TOMCAT_HOME}\"
ExecStart=${TOMCAT_HOME}/bin/startup.sh
ExecStop=${TOMCAT_HOME}/bin/shutdown.sh
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

echo "Systemd service file created at /etc/systemd/system/${TOMCAT_DIR}.service"

echo "----------------------------------------"
echo "  Reloading systemd daemon"
echo "----------------------------------------"

sudo systemctl daemon-reload

echo "----------------------------------------"
echo "  Starting Tomcat Service"
echo "----------------------------------------"

sudo systemctl start ${TOMCAT_DIR}

echo "----------------------------------------"
echo "  Enabling Tomcat on boot"
echo "----------------------------------------"

sudo systemctl enable ${TOMCAT_DIR}

echo "----------------------------------------"
echo "  Checking Tomcat Status"
echo "----------------------------------------"

sudo systemctl status ${TOMCAT_DIR} --no-page
