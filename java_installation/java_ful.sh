#!/bin/bash
set -e

echo "====================================================="
echo " STEP 0: Cleaning old Java variables from /root/.bashrc"
echo "====================================================="

BASHRC="/root/.bashrc"
BACKUP="/root/.bashrc.bak.$(date +%F_%H-%M-%S)"

# Backup existing .bashrc
cp "$BASHRC" "$BACKUP"
echo "Backup created: $BACKUP"

# Remove JAVA / TOMCAT related lines
sed -i \
  -e '/JAVA_HOME/d' \
  -e '/CATALINA_HOME/d' \
  -e '/TOMCAT_HOME/d' \
  -e '/java\/bin/d' \
  -e '/tomcat/d' \
  "$BASHRC"

echo "Old Java/Tomcat entries removed from /root/.bashrc"

# Reload bashrc
source "$BASHRC" || true
hash -r

echo "JAVA_HOME after cleanup: $JAVA_HOME"
echo

echo "====================================================="
echo " STEP 1: Installing Amazon Corretto Java 21"
echo "====================================================="

dnf install -y java-21-amazon-corretto-devel

echo "Java 21 installation completed"
echo

echo "====================================================="
echo " STEP 2: Set Java 21 as system default (keep Java 8)"
echo "====================================================="

alternatives --set java /usr/lib/jvm/java-21-amazon-corretto/bin/java
alternatives --set javac /usr/lib/jvm/java-21-amazon-corretto/bin/javac

echo "Java 21 set as default via alternatives"
echo

echo "====================================================="
echo " STEP 3: Configure JAVA_HOME globally"
echo "====================================================="

JAVA_HOME="/usr/lib/jvm/java-21-amazon-corretto"

cat > /etc/profile.d/java21.sh <<EOF
# Amazon Corretto Java 21
export JAVA_HOME=${JAVA_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF

chmod 644 /etc/profile.d/java21.sh

echo "JAVA_HOME configured in /etc/profile.d/java21.sh"
echo

echo "====================================================="
echo " STEP 4: Reload environment"
echo "====================================================="

source /etc/profile.d/java21.sh
hash -r

echo "JAVA_HOME = $JAVA_HOME"
echo

echo "====================================================="
echo " STEP 5: Runtime verification"
echo "====================================================="

echo "JAVA_HOME:"
echo "$JAVA_HOME"
echo

echo "java binary:"
type -a java
echo

echo "Resolved java path:"
readlink -f /usr/bin/java
echo

echo "Java version:"
java -version
echo

echo "Javac version:"
javac -version
echo

echo "Installed Java RPMs:"
rpm -qa | grep -i java
echo

echo "====================================================="
echo " ✅ Java 21 setup completed successfully"
echo "====================================================="
