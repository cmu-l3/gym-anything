#!/bin/bash
# set -euo pipefail

# ============================================================================
# OpenSIS LAMP Stack Installation Script
#
# Installs:
# - Apache 2.4+
# - MariaDB 10.4+ (MySQL-compatible)
# - PHP 8.x with required extensions
# - Google Chrome browser
# - OpenSIS v9.2 Student Information System
# - Verification tools (MySQL connector, screenshot tools)
# ============================================================================

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export NEEDRESTART_MODE=l
export APT_LISTCHANGES_FRONTEND=none

APT_GET_INSTALL_FLAGS=(
  -yq
  --no-install-recommends
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confold
)

echo "=== Installing OpenSIS LAMP Stack ==="

# ======= Configure APT mirrors =======
echo "Configuring APT mirrors..."

if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
fi

cat > /etc/apt/apt.conf.d/99custom << 'APT_CONF_EOF'
Acquire::Retries "3";
Acquire::http::Timeout "10";
Acquire::https::Timeout "10";
Acquire::ftp::Timeout "10";
Acquire::Queue-Mode "access";
Acquire::http::No-Cache "false";
APT_CONF_EOF

echo "APT configuration updated"

# Update package manager
apt-get update -yq

# Ensure debconf tools exist
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" debconf-utils

# Preseed common prompts
echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections || true
echo "postfix postfix/mailname string localhost" | debconf-set-selections || true

# Configure needrestart
mkdir -p /etc/needrestart/conf.d
cat > /etc/needrestart/conf.d/99-noninteractive.conf <<'NEEDRESTART_EOF'
$nrconf{restart} = 'l';
$nrconf{ui} = 'stdio';
NEEDRESTART_EOF

# ======= Install Apache Web Server =======
echo "Installing Apache web server..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    apache2 \
    libapache2-mod-php

# Enable required Apache modules
a2enmod rewrite
a2enmod headers
a2enmod ssl

echo "Apache installed successfully"

# ======= Install MariaDB (MySQL-compatible) =======
echo "Installing MariaDB server..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    mariadb-server \
    mariadb-client

echo "MariaDB installed successfully"

# ======= Install PHP 8.x with required extensions =======
echo "Installing PHP 8.x and extensions..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    php \
    php-mysql \
    php-mysqli \
    php-gd \
    php-curl \
    php-mbstring \
    php-xml \
    php-zip \
    php-intl \
    php-bcmath \
    php-json \
    php-common \
    php-cli

# Configure PHP for OpenSIS
PHP_INI=$(php -r "echo php_ini_loaded_file();")
if [ -n "$PHP_INI" ]; then
    echo "Configuring PHP settings in $PHP_INI..."
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
    sed -i 's/memory_limit = .*/memory_limit = 256M/' "$PHP_INI"
    sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
    sed -i 's/;date.timezone =.*/date.timezone = America\/New_York/' "$PHP_INI"
fi

# Also configure Apache's PHP ini
if [ -f /etc/php/*/apache2/php.ini ]; then
    for ini in /etc/php/*/apache2/php.ini; do
        sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$ini"
        sed -i 's/memory_limit = .*/memory_limit = 256M/' "$ini"
        sed -i 's/post_max_size = .*/post_max_size = 64M/' "$ini"
        sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$ini"
        sed -i 's/;date.timezone =.*/date.timezone = America\/New_York/' "$ini"
    done
fi

echo "PHP installed and configured successfully"

# ======= Install Google Chrome =======
echo "Installing Google Chrome..."
ARCH=$(uname -m)

if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ]; then
    apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
        wget \
        gnupg \
        ca-certificates \
        apt-transport-https

    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list

    apt-get update -yq
    apt-get install "${APT_GET_INSTALL_FLAGS[@]}" google-chrome-stable

    ln -sf /usr/bin/google-chrome-stable /usr/bin/chrome-browser
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    echo "Installing Chromium for ARM64..."
    apt-get install "${APT_GET_INSTALL_FLAGS[@]}" chromium-browser || {
        apt-get install "${APT_GET_INSTALL_FLAGS[@]}" chromium
    }
    ln -sf /usr/bin/chromium-browser /usr/bin/chrome-browser 2>/dev/null || \
    ln -sf /usr/bin/chromium /usr/bin/chrome-browser
fi

echo "Browser installed successfully"

# ======= Download and Install OpenSIS =======
echo "Downloading OpenSIS v9.2..."

OPENSIS_VERSION="V9.2"
OPENSIS_URL="https://github.com/OS4ED/openSIS-Classic/archive/refs/tags/${OPENSIS_VERSION}.tar.gz"
OPENSIS_DIR="/var/www/html/opensis"

apt-get install "${APT_GET_INSTALL_FLAGS[@]}" wget tar

# Download OpenSIS
wget -q -O /tmp/opensis.tar.gz "$OPENSIS_URL" || {
    echo "Failed to download from GitHub, trying alternative..."
    # Alternative: download from release assets
    wget -q -O /tmp/opensis.tar.gz "https://github.com/OS4ED/openSIS-Classic/archive/refs/heads/master.tar.gz"
}

# Extract to web directory
mkdir -p "$OPENSIS_DIR"
tar -xzf /tmp/opensis.tar.gz -C /tmp/
mv /tmp/openSIS-Classic-*/* "$OPENSIS_DIR/" 2>/dev/null || \
mv /tmp/openSIS-Classic-master/* "$OPENSIS_DIR/" 2>/dev/null || true

# Set proper ownership and permissions
chown -R www-data:www-data "$OPENSIS_DIR"
chmod -R 755 "$OPENSIS_DIR"

# Make specific directories writable
if [ -d "$OPENSIS_DIR/assets" ]; then
    chmod -R 775 "$OPENSIS_DIR/assets"
fi
if [ -d "$OPENSIS_DIR/tmp" ]; then
    chmod -R 775 "$OPENSIS_DIR/tmp"
fi
if [ -d "$OPENSIS_DIR/cache" ]; then
    chmod -R 775 "$OPENSIS_DIR/cache"
fi

rm -f /tmp/opensis.tar.gz
rm -rf /tmp/openSIS-Classic-*

echo "OpenSIS installed to $OPENSIS_DIR"

# ======= Install Verification Tools =======
echo "Installing verification and automation tools..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot \
    imagemagick \
    jq \
    python3-pip \
    python3-dev \
    python3-venv \
    python3-pil \
    python3-numpy

# Install Python MySQL connector for database verification
pip3 install --no-cache-dir \
    mysql-connector-python \
    pymysql \
    requests \
    beautifulsoup4 \
    selenium

echo "Verification tools installed successfully"

# ======= Install Additional Fonts =======
echo "Installing fonts for better web rendering..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    fonts-liberation \
    fonts-dejavu-extra \
    fonts-noto

# ======= Clean up =======
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== OpenSIS LAMP Stack installation completed ==="
