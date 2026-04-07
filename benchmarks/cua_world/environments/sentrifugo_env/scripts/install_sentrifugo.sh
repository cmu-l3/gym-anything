#!/bin/bash
# Sentrifugo Pre-Start Hook: Install Docker (for MySQL), Apache, PHP 7.4, Sentrifugo, browser, GUI tools
set -euo pipefail

echo "=== Installing Sentrifugo dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq

# Core tools
apt-get install -y \
    curl wget ca-certificates gnupg lsb-release software-properties-common \
    jq expect unzip \
    wmctrl xdotool scrot imagemagick xclip \
    python3 python3-pip \
    net-tools

# ============================================================
# Docker Engine (for MySQL container)
# ============================================================
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io

# Docker Compose v2 as plugin
COMPOSE_VERSION="v2.24.5"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL \
    "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Enable Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ga

# ============================================================
# PHP 7.4 from ondrej PPA (Sentrifugo requires PHP 7.x)
# ============================================================
add-apt-repository -y ppa:ondrej/php
apt-get update -qq

apt-get install -y \
    apache2 \
    php7.4 \
    libapache2-mod-php7.4 \
    php7.4-mysql \
    php7.4-gd \
    php7.4-curl \
    php7.4-xml \
    php7.4-mbstring \
    php7.4-zip \
    php7.4-json \
    php7.4-intl \
    php7.4-bcmath

# Disable any PHP 8.x modules that might be enabled by default
a2dismod php8.1 2>/dev/null || true
a2dismod php8.2 2>/dev/null || true
a2dismod php8.3 2>/dev/null || true
a2enmod php7.4
a2enmod rewrite

# Configure PHP for Sentrifugo
cat > /etc/php/7.4/apache2/conf.d/99-sentrifugo.ini << 'EOF'
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
max_input_time = 300
error_reporting = E_ALL & ~E_DEPRECATED & ~E_NOTICE & ~E_STRICT
display_errors = Off
date.timezone = America/New_York
EOF

# ============================================================
# Download Sentrifugo v3.2
# ============================================================
echo "Downloading Sentrifugo v3.2..."
cd /tmp
wget -q "https://sourceforge.net/projects/sentrifugo/files/Sentrifugo-v3.2.zip/download" \
    -O Sentrifugo-v3.2.zip || \
    wget -q "https://github.com/sapplica/sentrifugo/archive/refs/heads/master.zip" \
    -O Sentrifugo-v3.2.zip

echo "Extracting Sentrifugo..."
unzip -qo Sentrifugo-v3.2.zip -d /tmp/sentrifugo_extract

# Find the extracted directory (could be Sentrifugo/ or sentrifugo-master/)
EXTRACT_DIR=$(find /tmp/sentrifugo_extract -maxdepth 1 -type d ! -name sentrifugo_extract | head -1)
if [ -z "$EXTRACT_DIR" ]; then
    echo "ERROR: Could not find extracted Sentrifugo directory"
    ls -la /tmp/sentrifugo_extract/
    exit 1
fi

# Move to Apache document root
rm -rf /var/www/html/sentrifugo
mv "$EXTRACT_DIR" /var/www/html/sentrifugo

# Set permissions
chown -R www-data:www-data /var/www/html/sentrifugo
chmod -R 755 /var/www/html/sentrifugo

# Ensure writable directories
chmod -R 777 /var/www/html/sentrifugo/public/uploads 2>/dev/null || true
chmod -R 777 /var/www/html/sentrifugo/application/configs 2>/dev/null || true
chmod -R 777 /var/www/html/sentrifugo/logs 2>/dev/null || true
mkdir -p /var/www/html/sentrifugo/logs
chmod 777 /var/www/html/sentrifugo/logs

# ============================================================
# Configure Apache VirtualHost
# ============================================================
cat > /etc/apache2/sites-available/sentrifugo.conf << 'EOF'
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot /var/www/html/sentrifugo

    <Directory /var/www/html/sentrifugo>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/sentrifugo_error.log
    CustomLog ${APACHE_LOG_DIR}/sentrifugo_access.log combined
</VirtualHost>
EOF

a2dissite 000-default 2>/dev/null || true
a2ensite sentrifugo

# Enable proper URL rewriting in Sentrifugo root .htaccess
cat > /var/www/html/sentrifugo/.htaccess << 'HTACCESS'
Options +FollowSymLinks
RewriteEngine on

RewriteCond %{REQUEST_FILENAME} -s [OR]
RewriteCond %{REQUEST_FILENAME} -l [OR]
RewriteCond %{REQUEST_FILENAME} -d
RewriteRule ^.*$ - [NC,L]

RewriteRule ^.*$ index.php [NC,L]

SetEnv APPLICATION_ENV "production"
HTACCESS
chown www-data:www-data /var/www/html/sentrifugo/.htaccess

systemctl restart apache2

# ============================================================
# Firefox
# ============================================================
if command -v snap >/dev/null 2>&1; then
    snap install firefox 2>/dev/null || apt-get install -y firefox 2>/dev/null || true
else
    apt-get install -y firefox 2>/dev/null || true
fi

echo "=== Sentrifugo dependency installation complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version)"
echo "PHP version: $(php -v | head -1)"
echo "Apache version: $(apache2 -v | head -1)"
