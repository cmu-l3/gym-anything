#!/bin/bash
set -e

echo "=== Installing OrientDB ==="
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update -qq

# Install Java 11 (required for OrientDB)
apt-get install -y openjdk-11-jdk-headless

# Install GUI and utility tools
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    scrot \
    imagemagick \
    curl \
    wget \
    jq \
    python3 \
    python3-pip \
    net-tools \
    procps

# Set JAVA_HOME for current session only (do NOT modify /etc/environment - causes PATH corruption)
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

# Verify Java is working
java -version 2>&1 | head -1

# Download OrientDB Community Edition 3.2.36 from Maven Central
ORIENTDB_VERSION="3.2.36"
ORIENTDB_URL="https://repo1.maven.org/maven2/com/orientechnologies/orientdb-community/${ORIENTDB_VERSION}/orientdb-community-${ORIENTDB_VERSION}.tar.gz"
ORIENTDB_URL_FALLBACK="https://repo1.maven.org/maven2/com/orientechnologies/orientdb-community/3.2.27/orientdb-community-3.2.27.tar.gz"

echo "Downloading OrientDB ${ORIENTDB_VERSION}..."
cd /tmp

if wget -q --timeout=300 "$ORIENTDB_URL" -O orientdb-community.tar.gz; then
    echo "Downloaded OrientDB ${ORIENTDB_VERSION}"
else
    echo "Primary URL failed, trying fallback..."
    wget -q --timeout=300 "$ORIENTDB_URL_FALLBACK" -O orientdb-community.tar.gz
    echo "Downloaded fallback OrientDB"
fi

# Extract to /opt
tar xzf /tmp/orientdb-community.tar.gz -C /opt/
ORIENTDB_DIR=$(ls /opt/ | grep "orientdb-community" | sort -V | tail -1)
echo "Extracted to: /opt/${ORIENTDB_DIR}"

# Create versioned symlink
ln -sf "/opt/${ORIENTDB_DIR}" /opt/orientdb

# Make all scripts executable
chmod +x /opt/orientdb/bin/*.sh
find /opt/orientdb/bin -name "*.sh" -exec chmod +x {} \;

# Create orientdb system user
useradd -r -s /bin/false -d /opt/orientdb orientdb 2>/dev/null || echo "User orientdb already exists"

# Set ownership on the REAL directory path (not the symlink; chown -R doesn't follow symlinks)
chown -R orientdb:orientdb "/opt/${ORIENTDB_DIR}"

# Create systemd service for OrientDB
cat > /etc/systemd/system/orientdb.service << 'EOF'
[Unit]
Description=OrientDB Server
After=network.target

[Service]
Type=simple
User=orientdb
Group=orientdb
WorkingDirectory=/opt/orientdb
Environment=JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
Environment=ORIENTDB_HOME=/opt/orientdb
Environment=ORIENTDB_ROOT_PASSWORD=GymAnything123!
ExecStart=/opt/orientdb/bin/server.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable orientdb

# Increase system limits for OrientDB (Java-based, high file descriptor usage)
cat >> /etc/security/limits.conf << 'EOF'
orientdb soft nofile 65536
orientdb hard nofile 65536
root    soft nofile 65536
root    hard nofile 65536
EOF

echo "=== OrientDB installation complete ==="
echo "OrientDB version: ${ORIENTDB_VERSION}"
echo "OrientDB home: /opt/orientdb"
echo "Studio will be available at: http://localhost:2480/studio/index.html"
