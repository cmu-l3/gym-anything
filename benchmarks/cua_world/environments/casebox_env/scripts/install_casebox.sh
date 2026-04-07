#!/bin/bash
# Casebox Installation Script (pre_start hook)
# Installs PHP 7.4, Apache, MySQL (via Docker), and Casebox directly in the VM.

set -euo pipefail

echo "=== Installing Casebox prerequisites ==="

export DEBIAN_FRONTEND=noninteractive

echo "Updating package lists..."
apt-get update

# ============================================================
# 1. Install Docker (for MySQL container only)
# ============================================================
echo "Installing Docker..."
apt-get install -y docker.io docker-compose-v2
systemctl enable docker
systemctl start docker
usermod -aG docker ga || true

echo "dckr_pat_YISK01jQAaGVVmzkVoZnkOH3Q3g" | docker login -u "hackear2041" --password-stdin 2>/dev/null || true

echo "Pulling MySQL 5.7 Docker image..."
docker pull mysql:5.7 || true

# ============================================================
# 2. Install PHP 7.4 via ondrej PPA
# ============================================================
echo "Installing PHP 7.4..."
apt-get install -y software-properties-common
add-apt-repository ppa:ondrej/php -y 2>/dev/null || true
apt-get update

apt-get install -y \
    apache2 libapache2-mod-php7.4 \
    php7.4 php7.4-mysql php7.4-mbstring php7.4-xml php7.4-curl \
    php7.4-bcmath php7.4-json php7.4-tidy php7.4-intl php7.4-zip \
    php7.4-soap php7.4-cli php7.4-common php-imagick \
    || true

# Ensure PHP 7.4 is the default and Apache uses it
update-alternatives --set php /usr/bin/php7.4 2>/dev/null || true
a2dismod php8.5 php8.4 php8.3 php8.2 php8.1 2>/dev/null || true
a2enmod php7.4 2>/dev/null || true

# ============================================================
# 3. Install Composer
# ============================================================
echo "Installing Composer..."
curl -sS https://getcomposer.org/installer | php7.4 -- --install-dir=/usr/local/bin --filename=composer 2>/dev/null || true

# ============================================================
# 4. Install Firefox + automation tools
# ============================================================
echo "Installing Firefox + tools..."
apt-get install -y \
    firefox wmctrl xdotool x11-utils xclip scrot imagemagick \
    curl jq git ca-certificates netcat-openbsd redis-server mysql-client \
    python3 python3-pip || true

pip3 install --no-cache-dir requests >/dev/null 2>&1 || true

# ============================================================
# 5. Clone Casebox and install PHP dependencies
# ============================================================
echo "Cloning Casebox..."
git clone --depth 1 https://github.com/KETSE/casebox.git /var/www/casebox 2>&1 || true

if [ -d /var/www/casebox ]; then
    cd /var/www/casebox
    git config --global --add safe.directory /var/www/casebox

    # Pre-create parameters.yml
    mkdir -p app/config/default
    cp /workspace/config/parameters.yml app/config/default/parameters.yml

    # Fix composer.json for modern Composer compatibility
    python3 -c "
import json
with open('composer.json','r') as f:
    d = json.load(f)
d['name'] = 'ketse/casebox'
d['config'] = d.get('config', {})
d['config']['audit'] = {'block-insecure': False}
if 'require-dev' in d:
    d['require-dev'].pop('satooshi/php-coveralls', None)
with open('composer.json','w') as f:
    json.dump(d, f, indent=4)
"

    echo "Running composer install..."
    COMPOSER_ALLOW_SUPERUSER=1 php7.4 /usr/local/bin/composer install \
        --no-interaction --prefer-dist --ignore-platform-reqs --no-scripts 2>&1 | tail -5 || true

    # Dump autoload
    COMPOSER_ALLOW_SUPERUSER=1 php7.4 /usr/local/bin/composer dump-autoload --no-scripts 2>&1 || true

    # Disable platform check (legacy app needs PHP 7.4, some deps claim PHP 8.0+)
    cat > vendor/composer/platform_check.php << 'PHPEOF'
<?php
// Platform check disabled for legacy Casebox compatibility with PHP 7.4
PHPEOF

    # Set permissions
    mkdir -p var/cache var/logs var/files var/sessions
    chmod -R 777 var/cache var/logs var/files var/sessions
    chown -R www-data:www-data /var/www/casebox 2>/dev/null || true

    echo "Casebox installed"
else
    echo "ERROR: Failed to clone Casebox"
fi

# ============================================================
# 6. Configure Apache for Casebox
# ============================================================
echo "Configuring Apache..."
cp /workspace/config/casebox-apache.conf /etc/apache2/sites-available/casebox.conf
a2ensite casebox 2>/dev/null || true
a2dissite 000-default 2>/dev/null || true
a2enmod rewrite 2>/dev/null || true

apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation Complete ==="
echo "Docker: $(docker --version 2>/dev/null || echo 'not installed')"
echo "PHP: $(php7.4 --version 2>/dev/null | head -1 || echo 'not installed')"
echo "Apache: $(apache2 -v 2>/dev/null | head -1 || echo 'not installed')"
echo "Firefox: $(command -v firefox 2>/dev/null || echo 'not installed')"
echo "Casebox: $(ls /var/www/casebox/web/index.php 2>/dev/null && echo 'installed' || echo 'not installed')"
