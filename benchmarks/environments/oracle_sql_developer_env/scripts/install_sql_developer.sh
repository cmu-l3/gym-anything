#!/bin/bash
# Oracle SQL Developer Installation Script (pre_start hook)
# Installs Oracle SQL Developer, Docker, and Oracle Database XE image

echo "=== Installing Oracle SQL Developer Environment ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Install Docker and Docker Compose
echo "Installing Docker..."
apt-get install -y docker.io docker-compose
systemctl enable docker
systemctl start docker
usermod -aG docker ga

# Install Java 17 + JavaFX (required by SQL Developer)
echo "Installing Java JDK 17 + JavaFX..."
apt-get install -y openjdk-17-jdk openjfx

# Set JAVA_HOME system-wide
cat > /etc/profile.d/java.sh << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH
EOF
chmod +x /etc/profile.d/java.sh

# Install required dependencies
echo "Installing dependencies..."
apt-get install -y \
    wget \
    unzip \
    curl \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    imagemagick \
    python3-pip \
    libcanberra-gtk-module \
    libcanberra-gtk3-module

# Download Oracle SQL Developer (no-jre version)
# CRITICAL: Use otn_software path (no login required), NOT otn path (requires login)
echo "Downloading Oracle SQL Developer..."
SQLDEVELOPER_URL="https://download.oracle.com/otn_software/java/sqldeveloper/sqldeveloper-24.3.0.284.2209-no-jre.zip"
cd /tmp
wget -q --no-check-certificate -O sqldeveloper.zip "$SQLDEVELOPER_URL"

if [ -f /tmp/sqldeveloper.zip ] && [ -s /tmp/sqldeveloper.zip ]; then
    echo "Extracting SQL Developer to /opt/..."
    unzip -q /tmp/sqldeveloper.zip -d /opt/

    # Configure JAVA_HOME and JVM options for SQL Developer
    if [ -f /opt/sqldeveloper/sqldeveloper/bin/sqldeveloper.conf ]; then
        echo "SetJavaHome /usr/lib/jvm/java-17-openjdk-amd64" >> /opt/sqldeveloper/sqldeveloper/bin/sqldeveloper.conf
        # CRITICAL: Add --add-opens flags to prevent crashes with JDK 17 module system
        # Fixes: "factory already defined" (java.net), IllegalAccessException (sun.awt)
        cat >> /opt/sqldeveloper/sqldeveloper/bin/sqldeveloper.conf << 'VMEOF'
AddVMOption --add-opens=java.base/java.net=ALL-UNNAMED
AddVMOption --add-opens=java.base/java.lang=ALL-UNNAMED
AddVMOption --add-opens=java.base/sun.net.www.protocol.jar=ALL-UNNAMED
AddVMOption --add-opens=java.base/sun.net.www=ALL-UNNAMED
AddVMOption --add-opens=java.desktop/sun.awt=ALL-UNNAMED
AddVMOption --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED
AddVMOption --add-opens=java.desktop/javax.swing=ALL-UNNAMED
AddVMOption --add-opens=java.desktop/java.awt=ALL-UNNAMED
AddVMOption -Dsun.java2d.xrender=false
AddVMOption -Dsun.java2d.opengl=false
VMEOF
        echo "Added JVM module-open flags to sqldeveloper.conf"
    fi

    # Create jdk.conf and product.conf to set JAVA_HOME
    mkdir -p /opt/sqldeveloper/ide/bin
    cat > /opt/sqldeveloper/ide/bin/jdk.conf << 'JDKEOF'
SetJavaHome /usr/lib/jvm/java-17-openjdk-amd64
JDKEOF

    # Create product.conf with user-level JVM settings
    cat > /opt/sqldeveloper/ide/bin/product.conf << 'PRODUCTEOF'
AddVMOption --add-opens=java.base/java.net=ALL-UNNAMED
AddVMOption --add-opens=java.base/java.lang=ALL-UNNAMED
AddVMOption --add-opens=java.base/sun.net.www.protocol.jar=ALL-UNNAMED
AddVMOption --add-opens=java.base/sun.net.www=ALL-UNNAMED
AddVMOption --add-opens=java.desktop/sun.awt=ALL-UNNAMED
AddVMOption --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED
AddVMOption --add-opens=java.desktop/javax.swing=ALL-UNNAMED
AddVMOption --add-opens=java.desktop/java.awt=ALL-UNNAMED
AddVMOption -Dsun.java2d.xrender=false
AddVMOption -Dsun.java2d.opengl=false
PRODUCTEOF

    chmod +x /opt/sqldeveloper/sqldeveloper.sh

    # Create launcher wrapper with module-open flags and X11 rendering fixes
    cat > /usr/local/bin/sqldeveloper << 'LAUNCHEREOF'
#!/bin/bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH
# CRITICAL: JVM module flags to prevent crashes with JDK 17 module system
export JAVA_TOOL_OPTIONS="--add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/sun.net.www.protocol.jar=ALL-UNNAMED --add-opens=java.base/sun.net.www=ALL-UNNAMED --add-opens=java.desktop/sun.awt=ALL-UNNAMED --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED -Dsun.java2d.xrender=false -Dsun.java2d.opengl=false"
cd /opt/sqldeveloper
./sqldeveloper.sh "$@"
LAUNCHEREOF
    chmod +x /usr/local/bin/sqldeveloper

    echo "SQL Developer installed successfully at /opt/sqldeveloper/"
else
    echo "ERROR: SQL Developer download failed"
    exit 1
fi
rm -f /tmp/sqldeveloper.zip

# Download SQLcl (Oracle SQL command-line tool)
echo "Downloading SQLcl..."
wget -q --no-check-certificate -O /tmp/sqlcl.zip "https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip"
if [ -f /tmp/sqlcl.zip ] && [ -s /tmp/sqlcl.zip ]; then
    unzip -q /tmp/sqlcl.zip -d /opt/
    chmod +x /opt/sqlcl/bin/sql
    ln -sf /opt/sqlcl/bin/sql /usr/local/bin/sql
    echo "SQLcl installed"
fi
rm -f /tmp/sqlcl.zip

# Pre-pull Oracle XE Docker image
echo "Pulling Oracle Database XE Docker image..."
docker pull gvenzl/oracle-xe:21-slim || {
    echo "WARNING: Could not pull Oracle XE image - will retry during setup"
}

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation Complete ==="
echo "SQL Developer: $(ls /opt/sqldeveloper/sqldeveloper.sh 2>/dev/null && echo 'INSTALLED' || echo 'NOT FOUND')"
echo "SQLcl: $(which sql 2>/dev/null && echo 'INSTALLED' || echo 'NOT FOUND')"
echo "Docker: $(docker --version 2>/dev/null)"
echo "Java: $(java -version 2>&1 | head -1)"
echo "Oracle XE image: $(docker images gvenzl/oracle-xe --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || echo 'NOT PULLED')"
