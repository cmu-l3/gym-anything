#!/bin/bash
# WordPress Installation Script (pre_start hook)
# Installs Docker (for MariaDB) + Apache/PHP/WordPress natively on the VM
set -e

echo "=== Installing WordPress CMS ==="

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
# 2. Install Apache + PHP 8.2 + required extensions for WordPress
# ============================================================
echo "Installing Apache and PHP 8.2..."

# Add PHP 8.2 PPA
apt-get install -y software-properties-common
add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
apt-get update

apt-get install -y \
    apache2 \
    libapache2-mod-php8.2 \
    php8.2 \
    php8.2-bcmath \
    php8.2-curl \
    php8.2-dom \
    php8.2-gd \
    php8.2-intl \
    php8.2-mbstring \
    php8.2-mysql \
    php8.2-xml \
    php8.2-zip \
    php8.2-opcache \
    php8.2-cli \
    php8.2-common \
    php8.2-imagick \
    unzip \
    wget \
    git \
    curl \
    ca-certificates \
    jq

# ============================================================
# 3. Install WP-CLI
# ============================================================
echo "Installing WP-CLI..."
curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp
wp --info 2>/dev/null || echo "WP-CLI installed"

# ============================================================
# 4. Install Firefox and GUI automation tools
# ============================================================
echo "Installing Firefox and automation tools..."
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip

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
        sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$ini_file"
        sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$ini_file"
        sed -i 's/^post_max_size = .*/post_max_size = 64M/' "$ini_file"
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 64M/' "$ini_file"
        sed -i 's/^;max_input_vars = .*/max_input_vars = 5000/' "$ini_file"
        sed -i 's/^max_input_vars = .*/max_input_vars = 5000/' "$ini_file"
        if ! grep -q '^max_input_vars' "$ini_file"; then
            echo "max_input_vars = 5000" >> "$ini_file"
        fi
    fi
done

echo "PHP CLI memory_limit:"
php -r "echo 'memory_limit = ' . ini_get('memory_limit') . PHP_EOL;"

# ============================================================
# 7. Configure Apache for WordPress
# ============================================================
echo "Configuring Apache..."

cat > /etc/apache2/sites-available/wordpress.conf << 'APACHEEOF'
<VirtualHost *:80>
    ServerAdmin admin@localhost
    DocumentRoot /var/www/html/wordpress

    <Directory /var/www/html/wordpress>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/wordpress_error.log
    CustomLog ${APACHE_LOG_DIR}/wordpress_access.log combined
</VirtualHost>
APACHEEOF

a2dissite 000-default.conf 2>/dev/null || true
a2ensite wordpress.conf
a2enmod rewrite
a2enmod headers

systemctl enable apache2

# ============================================================
# 8. Download and Install WordPress
# ============================================================
echo "Downloading WordPress..."
mkdir -p /var/www/html

cd /var/www/html

# Download WordPress using WP-CLI
wp core download --path=/var/www/html/wordpress --allow-root 2>&1

# Set ownership
chown -R www-data:www-data /var/www/html/wordpress
chmod -R 755 /var/www/html/wordpress

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Apache: $(apache2 -v | head -1)"
echo "PHP: $(php -v | head -1)"
echo "WP-CLI: $(wp --version --allow-root 2>/dev/null || echo 'installed')"
echo "WordPress: $(ls /var/www/html/wordpress/wp-includes/version.php 2>/dev/null && echo 'downloaded' || echo 'not found')"
echo "Firefox: $(which firefox)"
echo ""
echo "WordPress will be configured in post_start hook"
