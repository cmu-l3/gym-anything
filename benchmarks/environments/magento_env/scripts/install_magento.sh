#!/bin/bash
# Magento Open Source Installation Script (pre_start hook)
# Installs Docker (for MariaDB + Elasticsearch) + Apache/PHP/Magento natively on the VM
set -e

echo "=== Installing Magento Open Source and Dependencies ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# ============================================================
# 1. Install Docker (for MariaDB + Elasticsearch containers)
# ============================================================
echo "Installing Docker..."
apt-get install -y docker.io docker-compose

systemctl enable docker
systemctl start docker
usermod -aG docker ga

# ============================================================
# 2. Install Apache + PHP 8.2 + required extensions for Magento
# ============================================================
echo "Installing Apache and PHP 8.2..."

# Add PHP 8.2 PPA (Ubuntu default may not have 8.2+)
apt-get install -y software-properties-common
add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
apt-get update

apt-get install -y \
    apache2 \
    libapache2-mod-php8.2 \
    php8.2 \
    php8.2-bcmath \
    php8.2-ctype \
    php8.2-curl \
    php8.2-dom \
    php8.2-gd \
    php8.2-intl \
    php8.2-mbstring \
    php8.2-mysql \
    php8.2-simplexml \
    php8.2-soap \
    php8.2-xsl \
    php8.2-zip \
    php8.2-xml \
    php8.2-opcache \
    php8.2-cli \
    php8.2-common \
    unzip \
    wget \
    git \
    curl \
    ca-certificates

# ============================================================
# 3. Install Composer
# ============================================================
echo "Installing Composer..."
export COMPOSER_ALLOW_SUPERUSER=1
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
    jq

# ============================================================
# 5. Install Python MySQL connector for verification
# ============================================================
echo "Installing Python MySQL connector..."
apt-get install -y python3-pip python3-pymysql
pip3 install --no-cache-dir mysql-connector-python PyMySQL 2>/dev/null || true

# ============================================================
# 6. Configure PHP 8.2
# ============================================================
echo "Configuring PHP 8.2..."

for ini_file in /etc/php/8.2/cli/php.ini /etc/php/8.2/apache2/php.ini; do
    if [ -f "$ini_file" ]; then
        echo "Configuring: $ini_file"
        sed -i 's/^memory_limit = .*/memory_limit = 2G/' "$ini_file"
        sed -i 's/^max_execution_time = .*/max_execution_time = 1800/' "$ini_file"
        sed -i 's/^zlib.output_compression = .*/zlib.output_compression = On/' "$ini_file"

        # Set max_input_vars
        sed -i 's/^;max_input_vars = .*/max_input_vars = 75000/' "$ini_file"
        sed -i 's/^max_input_vars = .*/max_input_vars = 75000/' "$ini_file"
        if ! grep -q '^max_input_vars' "$ini_file"; then
            echo "max_input_vars = 75000" >> "$ini_file"
        fi

        sed -i 's/^post_max_size = .*/post_max_size = 64M/' "$ini_file"
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 64M/' "$ini_file"
        sed -i 's/^;realpath_cache_size = .*/realpath_cache_size = 10M/' "$ini_file"
        sed -i 's/^;realpath_cache_ttl = .*/realpath_cache_ttl = 7200/' "$ini_file"
    fi
done

echo "PHP CLI memory_limit:"
php -r "echo 'memory_limit = ' . ini_get('memory_limit') . PHP_EOL;"

# ============================================================
# 7. Configure Apache for Magento
# ============================================================
echo "Configuring Apache..."

cat > /etc/apache2/sites-available/magento.conf << 'APACHEEOF'
<VirtualHost *:80>
    ServerAdmin admin@localhost
    DocumentRoot /var/www/html/magento/pub

    <Directory /var/www/html/magento/pub>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <Directory /var/www/html/magento>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/magento_error.log
    CustomLog ${APACHE_LOG_DIR}/magento_access.log combined
</VirtualHost>
APACHEEOF

a2dissite 000-default.conf 2>/dev/null || true
a2ensite magento.conf
a2enmod rewrite
a2enmod headers

systemctl enable apache2

# ============================================================
# 8. Download and Install Magento
# ============================================================
echo "Downloading Magento Open Source..."
export COMPOSER_ALLOW_SUPERUSER=1
mkdir -p /var/www/html

cd /var/www/html

# Method 1: Try Composer create-project (needs repo.magento.com auth)
echo "Trying Composer create-project..."
composer create-project --repository-url=https://repo.magento.com/ \
    magento/project-community-edition=2.4.7 magento \
    --no-interaction --no-dev 2>&1 && echo "Composer install succeeded" || {
    echo "Composer create-project failed (may need auth keys), trying GitHub archive..."
    rm -rf /var/www/html/magento 2>/dev/null

    # Method 2: Download from GitHub releases
    wget -q "https://github.com/magento/magento2/archive/refs/tags/2.4.7.tar.gz" -O /tmp/magento.tar.gz 2>&1 || {
        echo "GitHub download failed, trying with curl..."
        curl -L -o /tmp/magento.tar.gz "https://github.com/magento/magento2/archive/refs/tags/2.4.7.tar.gz" 2>&1
    }

    if [ -f /tmp/magento.tar.gz ]; then
        tar -xzf /tmp/magento.tar.gz -C /var/www/html/
        mv /var/www/html/magento2-2.4.7 /var/www/html/magento
        cd /var/www/html/magento
        echo "Running composer install..."
        composer install --no-dev --no-interaction 2>&1 || echo "Composer install had issues"
        rm -f /tmp/magento.tar.gz
    else
        echo "ERROR: Could not download Magento"
        exit 1
    fi
}

# Set ownership
chown -R www-data:www-data /var/www/html/magento
chmod -R 755 /var/www/html/magento

# Ensure var, generated, pub/static are writable
chmod -R 777 /var/www/html/magento/var
chmod -R 777 /var/www/html/magento/generated
chmod -R 777 /var/www/html/magento/pub/static
chmod -R 777 /var/www/html/magento/app/etc

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Apache: $(apache2 -v | head -1)"
echo "PHP: $(php -v | head -1)"
echo "Composer: $(composer --version 2>/dev/null | head -1)"
echo "Magento: $(ls /var/www/html/magento/bin/magento 2>/dev/null && echo 'installed' || echo 'not found')"
echo "Firefox: $(which firefox)"
echo ""
echo "Magento will be configured in post_start hook"
