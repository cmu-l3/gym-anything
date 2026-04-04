#!/bin/bash
# Drupal Commerce Installation Script (pre_start hook)
# Installs Docker (for MariaDB) + Apache/PHP/Composer/Drupal with Commerce module natively on the VM
set -e

echo "=== Installing Drupal Commerce ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# ============================================================
# 1. Install Docker (for MariaDB container)
# ============================================================
echo "Installing Docker..."
apt-get install -y docker.io docker-compose

systemctl enable docker
systemctl start docker
usermod -aG docker ga

# ============================================================
# 2. Install Apache + PHP 8.3 + required extensions for Drupal/Commerce
# ============================================================
echo "Installing Apache and PHP 8.3..."

# Add PHP 8.3 PPA
apt-get install -y software-properties-common
add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
apt-get update

apt-get install -y \
    apache2 \
    libapache2-mod-php8.3 \
    php8.3 \
    php8.3-bcmath \
    php8.3-curl \
    php8.3-dom \
    php8.3-gd \
    php8.3-intl \
    php8.3-mbstring \
    php8.3-mysql \
    php8.3-xml \
    php8.3-zip \
    php8.3-opcache \
    php8.3-cli \
    php8.3-common \
    php8.3-soap \
    php8.3-apcu \
    mariadb-client \
    unzip \
    wget \
    git \
    curl \
    ca-certificates \
    jq

# ============================================================
# 3. Install Composer
# ============================================================
echo "Installing Composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
composer --version 2>/dev/null || echo "Composer installed"

# ============================================================
# 4. Install Firefox and GUI automation tools
# ============================================================
echo "Installing Firefox and automation tools..."
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    scrot

# ============================================================
# 5. Install Python MySQL connector for verification
# ============================================================
echo "Installing Python MySQL connector..."
apt-get install -y python3-pip python3-pymysql
pip3 install --no-cache-dir mysql-connector-python PyMySQL 2>/dev/null || true

# ============================================================
# 6. Configure PHP 8.3
# ============================================================
echo "Configuring PHP 8.3..."

for ini_file in /etc/php/8.3/cli/php.ini /etc/php/8.3/apache2/php.ini; do
    if [ -f "$ini_file" ]; then
        echo "Configuring: $ini_file"
        sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$ini_file"
        sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$ini_file"
        sed -i 's/^post_max_size = .*/post_max_size = 64M/' "$ini_file"
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 64M/' "$ini_file"
        sed -i 's/^;max_input_vars = .*/max_input_vars = 10000/' "$ini_file"
        sed -i 's/^max_input_vars = .*/max_input_vars = 10000/' "$ini_file"
        if ! grep -q '^max_input_vars' "$ini_file"; then
            echo "max_input_vars = 10000" >> "$ini_file"
        fi
    fi
done

echo "PHP CLI memory_limit:"
php -r "echo 'memory_limit = ' . ini_get('memory_limit') . PHP_EOL;"

# ============================================================
# 7. Configure Apache for Drupal
# ============================================================
echo "Configuring Apache..."

cat > /etc/apache2/sites-available/drupal.conf << 'APACHEEOF'
<VirtualHost *:80>
    ServerAdmin admin@localhost
    DocumentRoot /var/www/html/drupal/web

    <Directory /var/www/html/drupal/web>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/drupal_error.log
    CustomLog ${APACHE_LOG_DIR}/drupal_access.log combined
</VirtualHost>
APACHEEOF

a2dissite 000-default.conf 2>/dev/null || true
a2ensite drupal.conf
a2enmod rewrite
a2enmod headers

systemctl enable apache2
systemctl restart apache2

# ============================================================
# 8. Download and Install Drupal with Commerce via Composer
# NOTE: This is the slowest step. If the pre_start hook times out
# here, the framework will checkpoint the VM and continue. The
# post_start hook will detect that Drupal isn't installed and the
# ensure_services_running() function in pre_task hooks will attempt
# to complete the installation.
# ============================================================
echo "Downloading Drupal with Commerce module..."
mkdir -p /var/www/html

cd /var/www/html

# Create Drupal project using recommended project template
export COMPOSER_ALLOW_SUPERUSER=1
composer create-project drupal/recommended-project drupal --no-interaction 2>&1

cd /var/www/html/drupal

# CRITICAL: Set minimum-stability to RC before requiring Commerce
# Commerce 3.x depends on inline_entity_form which is at RC stability
echo "Setting Composer minimum-stability to RC..."
composer config minimum-stability RC 2>&1

# Install Drush first (needed for site management)
echo "Installing Drush..."
composer require drush/drush --no-interaction 2>&1

# Install Commerce module and dependencies with -W flag to allow all dependency updates
echo "Installing Commerce module via Composer (this may take a few minutes)..."
composer require drupal/commerce -W --no-interaction 2>&1

# Install Admin Toolbar for better admin UX
echo "Installing Admin Toolbar..."
composer require drupal/admin_toolbar --no-interaction 2>&1 || true

# Set ownership
chown -R www-data:www-data /var/www/html/drupal
chmod -R 755 /var/www/html/drupal

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Apache: $(apache2 -v | head -1)"
echo "PHP: $(php -v | head -1)"
echo "Composer: $(composer --version 2>/dev/null)"
echo "Drush: $(cd /var/www/html/drupal && vendor/bin/drush --version 2>/dev/null || echo 'installed')"
echo "Firefox: $(which firefox)"
echo ""
echo "Drupal with Commerce will be configured in post_start hook"
