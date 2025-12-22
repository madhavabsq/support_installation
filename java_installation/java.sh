#!/bin/bash
set -e    # Exit immediately if any command fails. This ensures the script stops on the first error.

echo "-----------------------------------------------------"
echo " STEP 1: Installing Amazon Corretto Java 21 Devel"
echo "-----------------------------------------------------"
# Use DNF to install the specified Java package silently (-y).
sudo dnf install java-21-amazon-corretto-devel -y

# Check the exit status ($?) of the last executed command (dnf install).
# An exit status other than 0 (-ne 0) indicates a failure.
if [ $? -ne 0 ]; then
    echo "ERROR: Java installation failed."
    # Exit the script with a failure status (1).
    exit 1
fi

echo "Java installed successfully"
echo

echo "-----------------------------------------------------"
echo " STEP 2: Verify installation"
echo "-----------------------------------------------------"
# Execute the java command to confirm installation and print the version details.
java -version
echo

echo "-----------------------------------------------------"
echo " STEP 3: Setting JAVA_HOME + PATH in /etc/profile.d/java21.sh"
echo "-----------------------------------------------------"

# Find Java home dynamically:
# 1. 'which java' finds the path to the 'java' executable (e.g., /usr/bin/java).
# 2. 'readlink -f' resolves the symbolic link to the actual binary path.
# 3. '$(dirname $(dirname ...))' takes the parent directory of the 'bin' directory,
#    which correctly identifies the root installation path (JAVA_HOME).
JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))

# Use 'sudo tee'to write multiple lines to the file
# with root privileges. The '> /dev/null' suppresses tee's output (it echoes the content).
sudo tee /etc/profile.d/java21.sh > /dev/null << EOF
# Export the root path of the Java installation.
export JAVA_HOME=${JAVA_HOME}
# Append the Java bin directory to the system PATH variable.
export PATH=\$PATH:\$JAVA_HOME/bin
EOF

echo "JAVA_HOME and PATH updated"
echo

echo "-----------------------------------------------------"
echo " STEP 4: Reloading environment"
echo "-----------------------------------------------------"
# Source the new profile script to apply the JAVA_HOME and PATH changes immediately
# to the current shell session, allowing subsequent steps to use the variables.
source /etc/profile.d/java21.sh

echo "JAVA_HOME = $JAVA_HOME"
echo
echo "-----------------------------------------------------"
echo " STEP 4.1: Adding JAVA_HOME and PATH to ~/.bashrc"
echo "-----------------------------------------------------"

if ! grep -q "java-21-amazon-corretto" ~/.bashrc; then
    cat << EOF >> ~/.bashrc

# [Java Corretto 21]
export JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto.x86_64
export PATH=\$PATH:\$JAVA_HOME/bin
EOF

    echo "~/.bashrc updated successfully"
else
    echo "~/.bashrc already contains Java configuration — skipping"
fi

# Reload .bashrc immediately
source ~/.bashrc

echo "JAVA_HOME after sourcing ~/.bashrc = $JAVA_HOME"
echo

echo "-----------------------------------------------------"
echo " STEP 5: Checking alternatives (java)"
echo "-----------------------------------------------------"
# List all configured alternatives for the 'java' command.
# '|| true' ensures that 'set -e' doesn't exit the script if grep finds nothing.
sudo alternatives --list | grep java || true

echo
echo "If multiple java versions exist, please choose Java 21"
# Start the interactive tool to allow the user to select the default 'java' version.
# The script will pause here until the user makes a selection.
sudo alternatives --config java

echo

echo "-----------------------------------------------------"
echo " STEP 6: Checking alternatives (javac)"
echo "-----------------------------------------------------"
# List all configured alternatives for the 'javac' (Java compiler) command.
sudo alternatives --list | grep javac || true

echo
echo "If multiple javac versions exist, please choose Java 21"
# Start the interactive tool to allow the user to select the default 'javac' version.
# The script will pause here until the user makes a selection.
sudo alternatives --config javac

echo
echo "-----------------------------------------------------"
echo "Java 21 Installation Completed Successfully!"
echo "-----------------------------------------------------"
# Final verification of the active Java version.
java -version
# Print the set JAVA_HOME path.
echo "JAVA_HOME=${JAVA_HOME}"