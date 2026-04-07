#!/bin/bash
# Care2x HIS Installation Script (pre_start hook)
# Installs LAMP stack (Apache2 + PHP + MariaDB) and Care2x source code.

set -e

echo "=== Installing Care2x Hospital Information System ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install MariaDB server (Care2x uses MySQL-compatible database)
echo "Installing MariaDB..."
apt-get install -y mariadb-server mariadb-client

# Install Apache2 and PHP with required extensions
echo "Installing Apache2 and PHP..."
apt-get install -y \
    apache2 \
    libapache2-mod-php \
    php \
    php-mysql \
    php-gd \
    php-xml \
    php-mbstring \
    php-curl \
    php-zip \
    php-intl \
    php-bcmath \
    php-ldap

# Install Firefox (for browser-based interaction)
echo "Installing Firefox..."
apt-get install -y firefox

# Install GUI automation and screenshot tools
echo "Installing GUI automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    imagemagick \
    curl \
    jq \
    git \
    unzip \
    python3-pip

# Install Python packages
pip3 install --no-cache-dir requests 2>/dev/null || true

# Enable Apache modules
a2enmod rewrite

# Clone Care2x from GitHub
echo "Cloning Care2x from GitHub..."
cd /var/www/html
git clone https://github.com/care2x/care2x.git care2x

# Set permissions
chown -R www-data:www-data /var/www/html/care2x
chmod -R 755 /var/www/html/care2x

# Ensure writable directories exist
mkdir -p /var/www/html/care2x/cache
mkdir -p /var/www/html/care2x/uploads
chmod -R 777 /var/www/html/care2x/cache
chmod -R 777 /var/www/html/care2x/uploads
chmod -R 777 /var/www/html/care2x/installer

# Configure Apache VirtualHost for Care2x
cat > /etc/apache2/sites-available/care2x.conf << 'EOF'
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot /var/www/html/care2x

    <Directory /var/www/html/care2x>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/care2x_error.log
    CustomLog ${APACHE_LOG_DIR}/care2x_access.log combined
</VirtualHost>
EOF

# Enable the site and disable default
a2dissite 000-default.conf 2>/dev/null || true
a2ensite care2x.conf

# Configure PHP for Care2x
PHP_INI=$(php -r "echo php_ini_loaded_file();")
if [ -n "$PHP_INI" ]; then
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
    sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
    sed -i 's/memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
fi

# Also update Apache-specific PHP ini
APACHE_PHP_INI=$(find /etc/php -name "php.ini" -path "*/apache2/*" 2>/dev/null | head -1)
if [ -n "$APACHE_PHP_INI" ]; then
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$APACHE_PHP_INI"
    sed -i 's/post_max_size = .*/post_max_size = 64M/' "$APACHE_PHP_INI"
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$APACHE_PHP_INI"
    sed -i 's/memory_limit = .*/memory_limit = 512M/' "$APACHE_PHP_INI"
fi

# Enable and start services
systemctl enable mariadb
systemctl enable apache2

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Care2x installation complete ==="
echo "Apache: $(apache2 -v 2>/dev/null | head -1)"
echo "PHP: $(php -v 2>/dev/null | head -1)"
echo "MariaDB: $(mariadb --version 2>/dev/null)"
echo "Firefox: $(which firefox)"
echo "Care2x will be configured in post_start hook"
