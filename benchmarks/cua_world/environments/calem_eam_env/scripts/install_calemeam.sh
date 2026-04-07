#!/bin/bash
# CalemEAM Installation Script (pre_start hook)
# Installs Apache + PHP 7.4 natively, MySQL via Docker
# Downloads CalemEAM Community Edition R2.1e from GitHub
# Applies PHP 7.4 compatibility patches

set -e

echo "=== Installing CalemEAM Dependencies ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# ---- Docker for MySQL ----
echo "Installing Docker..."
apt-get install -y docker.io docker-compose
systemctl enable docker
systemctl start docker
usermod -aG docker ga

# ---- PHP 7.4 + Apache ----
echo "Installing PHP 7.4 and Apache..."
apt-get install -y software-properties-common
add-apt-repository -y ppa:ondrej/php
apt-get update

apt-get install -y \
    apache2 \
    libapache2-mod-php7.4 \
    php7.4 \
    php7.4-mysql \
    php7.4-xml \
    php7.4-mbstring \
    php7.4-curl \
    php7.4-gd \
    php7.4-intl \
    php7.4-zip \
    php7.4-bcmath \
    php7.4-json \
    php7.4-soap

# ---- GUI and automation tools ----
echo "Installing Firefox ESR and automation tools..."
# Use Firefox ESR from mozilla PPA for better legacy web app compatibility
add-apt-repository -y ppa:mozillateam/ppa
echo 'Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001' > /etc/apt/preferences.d/mozilla-firefox
apt-get update
# Remove snap firefox if present
snap remove firefox 2>/dev/null || true
apt-get install -y \
    firefox-esr \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    wget \
    unzip \
    git

# Python MySQL connector for verification
apt-get install -y python3-pip python3-pymysql
pip3 install --no-cache-dir mysql-connector-python PyMySQL || true

# ---- Configure PHP ----
echo "Configuring PHP..."
for ini_file in /etc/php/7.4/apache2/php.ini /etc/php/7.4/cli/php.ini; do
    if [ -f "$ini_file" ]; then
        sed -i 's/memory_limit = .*/memory_limit = 256M/' "$ini_file"
        sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$ini_file"
        sed -i 's/post_max_size = .*/post_max_size = 64M/' "$ini_file"
        sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$ini_file"
        sed -i 's/max_input_vars = .*/max_input_vars = 5000/' "$ini_file"
        # CalemEAM requires this error reporting level
        sed -i "s/error_reporting = .*/error_reporting = E_ALL \& ~E_NOTICE \& ~E_STRICT \& ~E_DEPRECATED/" "$ini_file"
        # Disable display_errors for production
        sed -i 's/^display_errors = .*/display_errors = Off/' "$ini_file"
    fi
done

# Ensure pdo_mysql is enabled via phpenmod (NOT via php.ini extension= line)
phpenmod pdo_mysql 2>/dev/null || true

# Enable Apache modules
a2enmod rewrite
a2enmod php7.4

# ---- Download CalemEAM ----
echo "Downloading CalemEAM Community Edition..."
cd /var/www/html
git clone https://github.com/calemcme/CalemEAM.git CalemEAM

# ---- Apply PHP 7.4 Compatibility Patches ----
echo "Applying PHP 7.4 compatibility patches..."
CALEM_DIR="/var/www/html/CalemEAM"

# Fix 1: CalemPDOStatement::bindValue - NULL data_type breaks queries in PHP 7.4
sed -i 's/return $this->pdoStmt->bindValue($parameter, $value, $data_type);/if ($data_type !== NULL) { return $this->pdoStmt->bindValue($parameter, $value, $data_type); } return $this->pdoStmt->bindValue($parameter, $value);/' \
    "$CALEM_DIR/server/include/core/database/CalemPDOStatement.php"

# Fix 2: CalemPDOStatement::fetch - NULL cursor params break in PHP 7.4
sed -i 's/return $this->pdoStmt->fetch($fetch_style, $cursor_orientation, $cursor_offset);/if ($cursor_orientation !== NULL) { return $this->pdoStmt->fetch($fetch_style, $cursor_orientation, $cursor_offset); } return $this->pdoStmt->fetch($fetch_style);/' \
    "$CALEM_DIR/server/include/core/database/CalemPDOStatement.php"

# Fix 3: CalemPdo::rollback - check inTransaction before rollback
sed -i 's/parent::rollback();/if (parent::inTransaction()) parent::rollback();/' \
    "$CALEM_DIR/server/include/core/database/CalemPdo.php"

# Fix 4: db_stmt_driver_options numeric array -> associative array
sed -i 's/array(PDO::ATTR_CURSOR, PDO::CURSOR_FWDONLY)/array(PDO::ATTR_CURSOR => PDO::CURSOR_FWDONLY)/' \
    "$CALEM_DIR/server/conf/calem.php"

# Fix 5: JsPkg.php - missing $ before variable name
sed -i 's/if (!js) {/if (!$js) {/' \
    "$CALEM_DIR/public/JsPkg.php"

# Fix 6: JsPkgCustom.php - null check before foreach on parentGroups
sed -i 's/foreach ($parentGroups as $grp)/if (is_array($parentGroups)) foreach ($parentGroups as $grp)/' \
    "$CALEM_DIR/public/JsPkgCustom.php"

# Fix 7: Create log4php.properties from sample
cp "$CALEM_DIR/etc/log4php.sample.properties" "$CALEM_DIR/etc/log4php.properties" 2>/dev/null || true

# Set permissions for CalemEAM
chown -R www-data:www-data "$CALEM_DIR"
chmod -R 755 "$CALEM_DIR"
chmod -R 777 "$CALEM_DIR/server/conf" 2>/dev/null || true
chmod -R 777 "$CALEM_DIR/client/launchpad" 2>/dev/null || true
chmod -R 777 "$CALEM_DIR/server/log" 2>/dev/null || true
chmod -R 777 "$CALEM_DIR/custom" 2>/dev/null || true
chmod -R 777 "$CALEM_DIR/server/setup" 2>/dev/null || true
mkdir -p "$CALEM_DIR/server/cache/data" "$CALEM_DIR/server/cache/session"
chmod -R 777 "$CALEM_DIR/server/cache"

# ---- Configure Apache for CalemEAM ----
echo "Configuring Apache..."
cat > /etc/apache2/sites-available/calemeam.conf << 'APACHECONF'
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot /var/www/html

    <Directory /var/www/html/CalemEAM>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/calemeam_error.log
    CustomLog ${APACHE_LOG_DIR}/calemeam_access.log combined
</VirtualHost>
APACHECONF

a2dissite 000-default.conf 2>/dev/null || true
a2ensite calemeam.conf

# Restart Apache
systemctl enable apache2
systemctl restart apache2

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "PHP version: $(php -v 2>/dev/null | head -1)"
echo "Apache: $(apache2 -v | head -1)"
echo "CalemEAM location: $CALEM_DIR"
echo ""
echo "CalemEAM will be configured in post_start hook"
