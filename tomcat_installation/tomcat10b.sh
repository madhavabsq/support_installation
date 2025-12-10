#!/bin/bash
set -e      # Exit immediately if any command fails.

echo "----------------------------------------------------"
echo " STEP 0: Updating System Packages"
echo "----------------------------------------------------"
sudo dnf update -y

echo "----------------------------------------"
echo "  STEP 1: Create tomcat10 group & user"
echo "----------------------------------------"

sudo groupadd tomcat10 || true
sudo useradd -M -s /usr/sbin/nologin -g tomcat10 -d /usr/share/tomcat10 tomcat10 || true

echo "Tomcat10 user & group created."

echo "----------------------------------------"
echo "  STEP 2: Download Apache Tomcat 10"
echo "----------------------------------------"

cd /tmp
TOMCAT_VERSION="10.1.49"
TOMCAT_FILE="apache-tomcat-${TOMCAT_VERSION}.tar.gz"

wget https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/${TOMCAT_FILE}

echo "Downloaded Tomcat ${TOMCAT_VERSION}"

echo "----------------------------------------"
echo "  STEP 3: Extract Tomcat to /usr/share/tomcat10"
echo "----------------------------------------"

sudo mkdir -p /usr/share/tomcat10
sudo tar -xvf ${TOMCAT_FILE} -C /usr/share/tomcat10 --strip-components=1

echo "Tomcat extracted."

echo "----------------------------------------"
echo "  STEP 4: Set directory permissions"
echo "----------------------------------------"

sudo chown -R tomcat10:tomcat10 /usr/share/tomcat10
sudo chmod -R 755 /usr/share/tomcat10

echo "Permissions set."

echo "----------------------------------------"
echo "  STEP 5: Make startup scripts executable"
echo "----------------------------------------"

sudo chmod +x /usr/share/tomcat10/bin/*.sh

echo "Tomcat installation setup complete!"

echo "----------------------------------------"
echo "  Creating Tomcat10 systemd service file"
echo "----------------------------------------"

sudo bash -c 'cat > /etc/systemd/system/tomcat10.service <<EOF
[Unit]
Description=Apache Tomcat10 Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat10
Group=tomcat10
Environment="JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto"
Environment="CATALINA_PID=/usr/share/tomcat10/temp/tomcat10.pid"
Environment="CATALINA_HOME=/usr/share/tomcat10"
Environment="CATALINA_BASE=/usr/share/tomcat10"
ExecStart=/usr/share/tomcat10/bin/startup.sh
ExecStop=/usr/share/tomcat10/bin/shutdown.sh
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF'

echo "Systemd service file created at /etc/systemd/system/tomcat10.service"

echo "----------------------------------------"
echo "  Reloading systemd daemon"
echo "----------------------------------------"

sudo systemctl daemon-reload

echo "----------------------------------------"
echo "  Starting Tomcat10 Service"
echo "----------------------------------------"

sudo systemctl start tomcat10

echo "----------------------------------------"
echo "  Enabling Tomcat10 on boot"
echo "----------------------------------------"

sudo systemctl enable tomcat10

echo "----------------------------------------"
echo "  Checking Tomcat10 Status"
echo "----------------------------------------"

sudo systemctl status tomcat10 --no-pager
