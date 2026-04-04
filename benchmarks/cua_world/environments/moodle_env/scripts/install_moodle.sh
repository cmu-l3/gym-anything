#!/bin/bash
# Moodle Installation Script (pre_start hook)
# Installs Docker (for MariaDB) + Apache/PHP/Moodle natively on the VM
set -e

echo "=== Installing Moodle and Dependencies ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# ============================================================
# 1. Install Docker (for MariaDB container only)
# ============================================================
echo "Installing Docker..."
apt-get install -y docker.io docker-compose

systemctl enable docker
systemctl start docker
usermod -aG docker ga

# ============================================================
# 2. Install Apache + PHP + required extensions for Moodle
# ============================================================
echo "Installing Apache and PHP..."
apt-get install -y \
    apache2 \
    libapache2-mod-php \
    php \
    php-mysql \
    php-xml \
    php-mbstring \
    php-curl \
    php-zip \
    php-gd \
    php-intl \
    php-soap \
    php-xmlrpc \
    php-json \
    php-bcmath \
    unzip \
    wget \
    git

# ============================================================
# 3. Install Firefox and GUI automation tools
# ============================================================
echo "Installing Firefox and automation tools..."
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    jq

# ============================================================
# 4. Install Python MySQL connector for verification
# ============================================================
echo "Installing Python MySQL connector..."
apt-get install -y python3-pip python3-pymysql
pip3 install --no-cache-dir mysql-connector-python PyMySQL || true

# ============================================================
# 5. Download and install Moodle
# ============================================================
echo "Downloading Moodle..."
MOODLE_VERSION="405"  # Moodle 4.5 stable
MOODLE_BRANCH="MOODLE_${MOODLE_VERSION}_STABLE"

cd /var/www/html
# Remove default Apache page
rm -f index.html

# Clone Moodle from official git repository (specific stable branch)
git clone --depth=1 -b "$MOODLE_BRANCH" https://github.com/moodle/moodle.git /var/www/html/moodle 2>&1 || {
    echo "Git clone failed, trying wget..."
    wget -q "https://download.moodle.org/download.php/direct/stable${MOODLE_VERSION}/moodle-latest-${MOODLE_VERSION}.tgz" -O /tmp/moodle.tgz
    tar -xzf /tmp/moodle.tgz -C /var/www/html/
    rm -f /tmp/moodle.tgz
}

# Create moodledata directory
mkdir -p /var/moodledata
chown -R www-data:www-data /var/moodledata
chmod 777 /var/moodledata

# Set ownership
chown -R www-data:www-data /var/www/html/moodle

# ============================================================
# 6. Configure PHP
# ============================================================
echo "Configuring PHP..."

# Configure ALL php.ini files (CLI + Apache + any others)
for ini_file in /etc/php/*/cli/php.ini /etc/php/*/apache2/php.ini; do
    if [ -f "$ini_file" ]; then
        echo "Configuring: $ini_file"
        # Handle both commented and uncommented max_input_vars
        sed -i 's/^;max_input_vars = .*/max_input_vars = 5000/' "$ini_file"
        sed -i 's/^max_input_vars = .*/max_input_vars = 5000/' "$ini_file"
        # If max_input_vars is still not present, add it
        if ! grep -q '^max_input_vars' "$ini_file"; then
            echo "max_input_vars = 5000" >> "$ini_file"
        fi
        sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$ini_file"
        sed -i 's/^post_max_size = .*/post_max_size = 50M/' "$ini_file"
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 50M/' "$ini_file"
    fi
done

# Verify the CLI setting
echo "Verifying PHP CLI max_input_vars:"
php -r "echo 'max_input_vars = ' . ini_get('max_input_vars') . PHP_EOL;"

# ============================================================
# 7. Configure Apache
# ============================================================
echo "Configuring Apache..."

# Create Apache config for Moodle
cat > /etc/apache2/sites-available/moodle.conf << 'APACHEEOF'
<VirtualHost *:80>
    ServerAdmin admin@localhost
    DocumentRoot /var/www/html/moodle

    <Directory /var/www/html/moodle>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/moodle_error.log
    CustomLog ${APACHE_LOG_DIR}/moodle_access.log combined
</VirtualHost>
APACHEEOF

# Enable the Moodle site and disable default
a2dissite 000-default.conf 2>/dev/null || true
a2ensite moodle.conf
a2enmod rewrite

# Enable Apache
systemctl enable apache2

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Apache: $(apache2 -v | head -1)"
echo "PHP: $(php -v | head -1)"
echo "Moodle: $(ls /var/www/html/moodle/version.php 2>/dev/null && echo 'installed' || echo 'not found')"
echo "Firefox: $(which firefox)"
echo ""
echo "Moodle will be configured in post_start hook"
