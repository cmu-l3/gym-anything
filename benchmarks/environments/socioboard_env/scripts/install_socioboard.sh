#!/bin/bash
# Socioboard 4.0 Installation Script (pre_start hook)
# Installs Apache, PHP 7.4, MariaDB, MongoDB, Node.js 14, and Socioboard 4.0 application.
# npm install and composer install run in background to avoid hook timeout.

set -e

echo "=== Installing Socioboard 4.0 prerequisites ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

echo "--- Installing core system utilities ---"
apt-get install -y \
  curl wget git unzip gnupg2 ca-certificates \
  lsb-release software-properties-common \
  wmctrl xdotool x11-utils xclip scrot imagemagick \
  netcat-openbsd jq python3 python3-pip \
  2>/dev/null

echo "--- Installing Apache2 ---"
apt-get install -y apache2
a2enmod rewrite
systemctl enable apache2

echo "--- Installing PHP 7.4 (via ondrej/php PPA) ---"
# Ubuntu 22.04 ships PHP 8.1 by default; we need PHP 7.4 for Socioboard 4.0
add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
apt-get update
apt-get install -y \
  php7.4 php7.4-cli php7.4-common php7.4-mysql \
  php7.4-zip php7.4-gd php7.4-mbstring php7.4-curl \
  php7.4-xml php7.4-bcmath \
  libapache2-mod-php7.4
# php7.4-json and php7.4-tokenizer are bundled in 7.4 core
update-alternatives --set php /usr/bin/php7.4 2>/dev/null || true
update-alternatives --set phar /usr/bin/phar7.4 2>/dev/null || true

echo "--- Installing Composer ---"
curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
# COMPOSER_ALLOW_SUPERUSER=1 suppresses the interactive root-user prompt
COMPOSER_ALLOW_SUPERUSER=1 php7.4 /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
COMPOSER_ALLOW_SUPERUSER=1 composer --version

echo "--- Installing MariaDB ---"
apt-get install -y mariadb-server mariadb-client
systemctl enable mariadb

echo "--- Installing MongoDB 7.0 for Ubuntu 22.04 ---"
# MongoDB 7.0 supports Ubuntu 22.04 (jammy)
wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | \
  gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-7.0.list
apt-get update
apt-get install -y mongodb-org
systemctl enable mongod

echo "--- Installing Node.js 16 ---"
# Node.js 16 is compatible with Socioboard 4.0 microservices (14 is EOL)
curl -fsSL https://deb.nodesource.com/setup_16.x | bash - 2>/dev/null || \
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs
node --version
npm --version

echo "--- Installing global Node packages ---"
npm install -g pm2 nodemon sequelize-cli mysql2 2>/dev/null || true
pm2 --version

echo "--- Installing Firefox + automation tools ---"
apt-get install -y firefox wmctrl 2>/dev/null || \
  apt-get install -y firefox-esr wmctrl 2>/dev/null || true

echo "--- Cloning Socioboard 4.0 repository ---"
git clone --depth=1 https://github.com/socialbotspy/Socioboard-4.0.git /opt/socioboard 2>/dev/null || \
  git clone --depth=1 https://github.com/socioboard/Socioboard-5.0.git --branch Socioboard-4.0 /opt/socioboard 2>/dev/null || \
  git clone --depth=1 https://github.com/criptalis/Socioboard-4.0.git /opt/socioboard 2>/dev/null || true

if [ ! -d "/opt/socioboard" ]; then
  echo "ERROR: Failed to clone Socioboard repository"
  exit 1
fi

echo "Socioboard cloned to /opt/socioboard"
ls /opt/socioboard/

echo "--- Starting npm install + composer install in background ---"
# These can take 15-25 minutes, so run in background and create marker file when done

cat > /tmp/install_socioboard_bg.sh << 'BGSCRIPT'
#!/bin/bash
set -e
LOG=/tmp/socioboard_bg_install.log
exec > "$LOG" 2>&1
echo "Background install started at $(date)"

SOCRDIR=/opt/socioboard

# Install npm packages for each microservice
for SVC in feeds library notification publish user; do
  SVC_DIR="$SOCRDIR/socioboard-api/$SVC"
  if [ -d "$SVC_DIR" ]; then
    echo "npm install for $SVC ..."
    cd "$SVC_DIR"
    npm install --legacy-peer-deps --no-audit 2>&1 | tail -5 || \
      npm install --no-audit 2>&1 | tail -5 || true
    echo "$SVC done"
  else
    echo "WARNING: $SVC_DIR not found, skipping"
  fi
done

# Also install for sequelize-cli
if [ -d "$SOCRDIR/socioboard-api/library/sequelize-cli" ]; then
  cd "$SOCRDIR/socioboard-api/library/sequelize-cli"
  npm install --legacy-peer-deps --no-audit 2>&1 | tail -5 || true
  echo "sequelize-cli done"
fi

# Install PHP Composer packages for frontend
PHPDIR="$SOCRDIR/socioboard-web-php"
if [ -d "$PHPDIR" ]; then
  cd "$PHPDIR"
  echo "Composer install..."
  # Copy environmentfile.env to .env if it exists
  [ -f environmentfile.env ] && cp environmentfile.env .env
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-interaction --no-progress 2>&1 | tail -10 || \
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-interaction --no-progress --ignore-platform-reqs 2>&1 | tail -10 || true
  echo "Composer done"
fi

echo "Background install completed at $(date)"
touch /tmp/socioboard_install_complete.marker
BGSCRIPT

chmod +x /tmp/install_socioboard_bg.sh
nohup bash /tmp/install_socioboard_bg.sh > /tmp/socioboard_bg_install.log 2>&1 &
BG_PID=$!
echo "Background install started (PID: $BG_PID)"

# Fix permissions
chown -R ga:ga /opt/socioboard 2>/dev/null || true

echo ""
echo "=== Socioboard installation prerequisites complete ==="
echo "Background npm/composer install running (PID: $BG_PID)"
echo "post_start hook will wait for marker: /tmp/socioboard_install_complete.marker"
