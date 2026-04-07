#!/bin/bash
# Animal Shelter Manager 3 (ASM3) Installation Script (pre_start hook)
# Installs PostgreSQL, Python dependencies, and ASM3 from source

set -e

echo "=== Installing Animal Shelter Manager 3 ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install PostgreSQL
echo "Installing PostgreSQL..."
apt-get install -y postgresql postgresql-contrib

# Install Python dependencies
echo "Installing Python3 and dependencies..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-pil \
    python3-psycopg2 \
    python3-setuptools \
    python3-requests \
    python3-reportlab

# Install additional Python packages via pip
pip3 install --no-cache-dir \
    cheroot \
    pillow \
    psycopg2-binary \
    requests \
    reportlab \
    openpyxl \
    qrcode \
    lxml 2>/dev/null || true

# Install Firefox browser
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
    scrot \
    imagemagick \
    git \
    jq

# Clone ASM3 from GitHub
echo "Cloning ASM3 from GitHub..."
if [ -d /opt/asm3 ]; then
    rm -rf /opt/asm3
fi
git clone --depth 1 https://github.com/sheltermanager/asm3.git /opt/asm3

# Set permissions
chown -R ga:ga /opt/asm3

# Start PostgreSQL and create database
echo "Setting up PostgreSQL database..."
systemctl enable postgresql
systemctl start postgresql

# Wait for PostgreSQL to be ready
for i in {1..30}; do
    if su - postgres -c "pg_isready" 2>/dev/null; then
        echo "PostgreSQL is ready after ${i}s"
        break
    fi
    sleep 1
done

# Create ASM database and user
su - postgres -c "psql -c \"CREATE USER asm WITH PASSWORD 'asm';\"" 2>/dev/null || true
su - postgres -c "psql -c \"CREATE DATABASE asm OWNER asm;\"" 2>/dev/null || true
su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE asm TO asm;\"" 2>/dev/null || true

# Configure PostgreSQL to allow local password auth
PG_HBA=$(find /etc/postgresql -name pg_hba.conf 2>/dev/null | head -1)
if [ -n "$PG_HBA" ]; then
    # Add md5 auth for local connections before the default peer line
    sed -i 's/local\s\+all\s\+all\s\+peer/local   all             all                                     md5/' "$PG_HBA"
    # Also allow password auth over TCP
    sed -i 's|host\s\+all\s\+all\s\+127.0.0.1/32\s\+.*|host    all             all             127.0.0.1/32            md5|' "$PG_HBA"
    systemctl restart postgresql
fi

# Wait for PostgreSQL restart
for i in {1..15}; do
    if su - postgres -c "pg_isready" 2>/dev/null; then
        echo "PostgreSQL restarted successfully"
        break
    fi
    sleep 1
done

# Generate __version__.py (normally done by make dist)
echo "Generating ASM3 version file..."
VERSION=$(cat /opt/asm3/VERSION 2>/dev/null || echo "dev")
cat > /opt/asm3/src/asm3/__version__.py << VEREOF
VERSION = "${VERSION} [$(date)]"
BUILD = "$(date +%m%d%H%M%S)"
VEREOF

# Copy ASM3 configuration
echo "Configuring ASM3..."
cp /workspace/config/asm3.conf /opt/asm3/src/asm3.conf
cp /workspace/config/asm3.conf /etc/asm3.conf

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "PostgreSQL: $(psql --version 2>/dev/null || echo 'installed')"
echo "Python3: $(python3 --version)"
echo "Firefox: $(which firefox)"
echo "ASM3 source: /opt/asm3"
echo ""
echo "ASM3 will be started in post_start hook"
