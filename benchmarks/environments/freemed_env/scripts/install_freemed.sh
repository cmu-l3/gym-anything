#!/bin/bash
# FreeMED Installation Script (pre_start hook)
# Installs LAMP stack (Apache + MySQL + PHP 7.4) for FreeMED
# FreeMED uses PHP 5/7 era code incompatible with PHP 8.x - use PHP 7.4

set -e

echo "=== Installing FreeMED LAMP Stack ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update -qq

# Install base tools
apt-get install -y \
    software-properties-common \
    curl \
    wget \
    git \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    imagemagick \
    scrot \
    python3-pip \
    2>/dev/null

# Add PHP 7.4 PPA (ondrej/php) - FreeMED needs PHP 7.x (PHP 8.x breaks API.php)
add-apt-repository -y ppa:ondrej/php 2>&1 | tail -3
apt-get update -qq

# Install Apache, MySQL, PHP 7.4 and required extensions
apt-get install -y \
    apache2 \
    mysql-server \
    php7.4 \
    php7.4-mysql \
    php7.4-xml \
    php7.4-gd \
    php7.4-mbstring \
    php7.4-curl \
    php7.4-zip \
    php7.4-intl \
    libapache2-mod-php7.4 \
    2>/dev/null

# Enable required Apache modules
a2enmod rewrite
a2enmod php7.4 2>/dev/null || true

# Install Firefox for web UI interaction (snap version)
apt-get install -y firefox 2>/dev/null || snap install firefox 2>/dev/null || true

# Install Python MySQL connector for verification
pip3 install --no-cache-dir mysql-connector-python PyMySQL 2>/dev/null || true

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== FreeMED LAMP Stack Installation Complete ==="
echo "Apache: $(apache2 -v 2>/dev/null | head -1 || echo 'installed')"
echo "MySQL: $(mysql --version 2>/dev/null || echo 'installed')"
echo "PHP: $(php7.4 -v 2>/dev/null | head -1 || echo 'installed')"
