#!/bin/bash
set -e      # Exit immediately if any command fails. This ensures the script stops on the first error.

echo "----------------------------------------------------"
echo " STEP 0: Updating System Packages"
echo "----------------------------------------------------"
sudo dnf update -y

echo "----------------------------------------"
echo "  STEP 1: Create tomcat group & user"
echo "----------------------------------------"

sudo groupadd tomcat || true
sudo useradd -M -s /usr/sbin/nologin -g tomcat -d /usr/share/tomcat tomcat || true

echo "Tomcat user & group created."

echo "----------------------------------------"
echo "  STEP 2: Download Apache Tomcat 10"
echo "----------------------------------------"

cd /tmp

echo "Press 1 for latest Tomcat version."
echo "Press 2 if you want to enter a particular Tomcat version:"
read num

if [ "$num" -eq 1 ]; then
    TOMCAT_VERSION="10.1.49"
    TOMCAT_FILE="apache-tomcat-${TOMCAT_VERSION}.tar.gz"

    wget "https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/${TOMCAT_FILE}"

    echo "Downloaded Tomcat ${TOMCAT_VERSION}"

else
    echo "Enter the Tomcat version you want (example: 10.1.42): "
    read TOMCAT_VERSION

    TOMCAT_FILE="apache-tomcat-${TOMCAT_VERSION}-src.tar.gz"

    wget "https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/src/${TOMCAT_FILE}"

    echo "Downloaded Tomcat ${TOMCAT_VERSION}"
fi


echo "----------------------------------------"
echo "  STEP 3: Extract Tomcat to /usr/share/tomcat"
echo "----------------------------------------"

sudo mkdir -p /usr/share/tomcat
sudo tar -xvf ${TOMCAT_FILE} -C /usr/share/tomcat --strip-components=1

echo "Tomcat extracted."

echo "----------------------------------------"
echo "  STEP 4: Set directory permissions"
echo "----------------------------------------"

sudo chown -R tomcat:tomcat /usr/share/tomcat
sudo chmod -R 755 /usr/share/tomcat

echo "Permissions set."

echo "----------------------------------------"
echo "  STEP 5: Make startup scripts executable"
echo "----------------------------------------"

sudo chmod +x /usr/share/tomcat/bin/*.sh

echo "Tomcat installation setup complete!"

echo "----------------------------------------"
echo "  Creating Tomcat systemd service file"
echo "----------------------------------------"

sudo bash -c 'cat > /etc/systemd/system/tomcat.service <<EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto"
Environment="CATALINA_PID=/usr/share/tomcat/temp/tomcat.pid"
Environment="CATALINA_HOME=/usr/share/tomcat"
Environment="CATALINA_BASE=/usr/share/tomcat"
ExecStart=/usr/share/tomcat/bin/startup.sh
ExecStop=/usr/share/tomcat/bin/shutdown.sh
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF'

echo "Systemd service file created at /etc/systemd/system/tomcat.service"


echo "----------------------------------------"
echo "  Reloading systemd daemon"
echo "----------------------------------------"

sudo systemctl daemon-reload


echo "----------------------------------------"
echo "  Starting Tomcat Service"
echo "----------------------------------------"

sudo systemctl start tomcat


echo "----------------------------------------"
echo "  Enabling Tomcat on boot"
echo "----------------------------------------"

sudo systemctl enable tomcat


echo "----------------------------------------"
echo "  Checking Tomcat Status"
echo "----------------------------------------"

sudo systemctl status tomcat --no-pager



#CATALINA_HOME=/usr/share/tomcat10
export JAVA_HOME
export CATALINA_HOME
PATH=$JAVA_HOME/bin:$CATALINA_HOME/bin:$PATH
export PATH