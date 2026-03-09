#!/bin/bash
# Oracle Database XE Installation Script (pre_start hook)
# Installs Docker and Oracle Database XE via official Oracle Docker image
# Also installs SQL Developer (GUI tool) and SQLcl (command-line tool)

set -e

echo "=== Installing Oracle Database XE Environment ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker and Docker Compose
echo "Installing Docker..."
apt-get install -y docker.io docker-compose

# Start and enable Docker service
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Install Firefox browser for SQL Developer web access
echo "Installing Firefox..."
apt-get install -y firefox

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    wget \
    unzip

# Install Java (required for SQL Developer)
echo "Installing Java 17..."
apt-get install -y openjdk-17-jdk openjdk-17-jre

# Set JAVA_HOME
echo "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64" >> /etc/profile.d/java.sh
echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> /etc/profile.d/java.sh
chmod +x /etc/profile.d/java.sh

# Install Python tools for verification
echo "Installing Python tools..."
apt-get install -y python3-pip
pip3 install --no-cache-dir cx_Oracle oracledb || true

# Install SQLcl (Oracle SQL Command Line)
echo "Installing SQLcl..."
SQLCL_URL="https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip"
mkdir -p /opt/sqlcl
cd /tmp
wget -q "$SQLCL_URL" -O sqlcl.zip || echo "SQLcl download may require manual install"
if [ -f sqlcl.zip ]; then
    unzip -o -q sqlcl.zip -d /opt/
    chmod +x /opt/sqlcl/bin/sql
    ln -sf /opt/sqlcl/bin/sql /usr/local/bin/sql
    echo "SQLcl installed"
else
    echo "Warning: SQLcl not downloaded - will use SQL*Plus from Docker container"
fi
rm -f sqlcl.zip

# Install SQL Developer (GUI tool)
echo "Installing SQL Developer..."
SQLDEVELOPER_URL="https://download.oracle.com/otn_software/java/sqldeveloper/sqldeveloper-23.1.0.097.1607-no-jre.zip"
cd /tmp
wget -q "$SQLDEVELOPER_URL" -O sqldeveloper.zip || echo "SQL Developer download may require Oracle account"
if [ -f sqldeveloper.zip ]; then
    unzip -o -q sqldeveloper.zip -d /opt/
    chmod +x /opt/sqldeveloper/sqldeveloper.sh

    # Create launcher script
    cat > /usr/local/bin/sqldeveloper << 'EOF'
#!/bin/bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
cd /opt/sqldeveloper
./sqldeveloper.sh "$@"
EOF
    chmod +x /usr/local/bin/sqldeveloper
    echo "SQL Developer installed"
else
    echo "Warning: SQL Developer not downloaded - will use DBeaver as alternative"
    # Install DBeaver as alternative GUI
    apt-get install -y dbeaver-ce || snap install dbeaver-ce || true
fi
rm -f sqldeveloper.zip

# Pull Oracle XE Docker image
echo "Pulling Oracle Database XE Docker image..."
# Oracle provides official images via container-registry.oracle.com
# For development, we use the gvenzl/oracle-xe image which is easier to use
docker pull gvenzl/oracle-xe:21-slim || docker pull gvenzl/oracle-xe:latest || {
    echo "Warning: Could not pull Oracle XE image - will try during setup"
}

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Oracle Database XE Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Java version: $(java -version 2>&1 | head -1)"
echo ""
echo "Oracle Database XE will be started via Docker in post_start hook"
