#!/bin/bash
set -e    # Exit immediately if any command fails.

echo "-----------------------------------------------------"
echo " STEP 0: Checking existing Java version"
echo "-----------------------------------------------------"

JAVA_OUTPUT=""
if command -v java &>/dev/null; then
    JAVA_OUTPUT=$(java -version 2>&1)
fi

echo "$JAVA_OUTPUT"
echo

# -----------------------------------------------------
# Clean ~/.bashrc ONLY if Java is NOT version 21
# -----------------------------------------------------
if ! echo "$JAVA_OUTPUT" | grep -q 'version "21'; then
    echo "Java 21 not detected → cleaning old Java entries from ~/.bashrc"

    sed -i \
      -e '/JAVA_HOME/d' \
      -e '/java-.*corretto/d' \
      -e '/java\/bin/d' \
      ~/.bashrc || true
else
    echo "Java 21 already detected → skipping ~/.bashrc cleanup"
fi

echo
echo "-----------------------------------------------------"
echo " STEP 1: Installing Amazon Corretto Java 21 Devel"
echo "-----------------------------------------------------"

sudo dnf install -y java-21-amazon-corretto-devel

echo "Java installed successfully"
echo

echo "-----------------------------------------------------"
echo " STEP 2: Verify installation"
echo "-----------------------------------------------------"

java -version
echo

echo "-----------------------------------------------------"
echo " STEP 3: Setting JAVA_HOME + PATH in /etc/profile.d/java21.sh"
echo "-----------------------------------------------------"

JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))

sudo tee /etc/profile.d/java21.sh > /dev/null << EOF
# Amazon Corretto Java 21
export JAVA_HOME=${JAVA_HOME}
export PATH=\$PATH:\$JAVA_HOME/bin
EOF

echo "JAVA_HOME and PATH updated globally"
echo

echo "-----------------------------------------------------"
echo " STEP 4: Reloading environment"
echo "-----------------------------------------------------"

source /etc/profile.d/java21.sh
hash -r

echo "JAVA_HOME = $JAVA_HOME"
echo

echo "-----------------------------------------------------"
echo " STEP 4.1: Adding JAVA_HOME and PATH to ~/.bashrc (if missing)"
echo "-----------------------------------------------------"

if ! grep -q "java-21-amazon-corretto" ~/.bashrc; then
    cat << EOF >> ~/.bashrc

# [Java Corretto 21]
export JAVA_HOME=${JAVA_HOME}
export PATH=\$PATH:\$JAVA_HOME/bin
EOF
    echo "~/.bashrc updated successfully"
else
    echo "~/.bashrc already contains Java configuration — skipping"
fi

source ~/.bashrc || true

echo "JAVA_HOME after sourcing ~/.bashrc = $JAVA_HOME"
echo

echo "-----------------------------------------------------"
echo " STEP 5: Checking alternatives (java)"
echo "-----------------------------------------------------"

sudo alternatives --list | grep java || true
echo
sudo alternatives --config java

echo
echo "-----------------------------------------------------"
echo " STEP 6: Checking alternatives (javac)"
echo "-----------------------------------------------------"

sudo alternatives --list | grep javac || true
echo
sudo alternatives --config javac

echo
echo "-----------------------------------------------------"
echo " Java 21 Installation Completed Successfully!"
echo "-----------------------------------------------------"

java -version
echo "JAVA_HOME=${JAVA_HOME}"
