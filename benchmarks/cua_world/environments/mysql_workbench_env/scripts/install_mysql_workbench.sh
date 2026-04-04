#!/bin/bash
# MySQL Workbench Installation Script (pre_start hook)
# Installs MySQL Server and MySQL Workbench for database management tasks

set -e

echo "=== Installing MySQL Server and MySQL Workbench ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Preconfigure MySQL root password to avoid interactive prompts
debconf-set-selections <<< "mysql-server mysql-server/root_password password GymAnything#2024"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password GymAnything#2024"

# Update package lists
echo "Updating package lists..."
apt-get update

# Install MySQL Server
echo "Installing MySQL Server..."
apt-get install -y mysql-server mysql-client

# Install MySQL Workbench via snap (most reliable method for Ubuntu 22.04+)
echo "Installing MySQL Workbench via snap..."
snap install mysql-workbench-community

# Connect snap permissions for password manager
snap connect mysql-workbench-community:password-manager-service :password-manager-service 2>/dev/null || true
snap connect mysql-workbench-community:ssh-keys :ssh-keys 2>/dev/null || true

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    scrot \
    curl \
    wget \
    unzip

# Install Python packages for verification scripts
apt-get install -y python3-pip
pip3 install --no-cache-dir --break-system-packages pymysql 2>/dev/null || \
pip3 install --no-cache-dir pymysql 2>/dev/null || true

# Start MySQL service
echo "Starting MySQL service..."
systemctl enable mysql
systemctl start mysql

# Wait for MySQL to be ready
echo "Waiting for MySQL to start..."
MYSQL_READY=false
for i in {1..30}; do
    if mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
        MYSQL_READY=true
        echo "MySQL is ready after ${i}s"
        break
    fi
    sleep 1
done

if [ "$MYSQL_READY" = false ]; then
    echo "WARNING: MySQL may not be ready yet"
fi

# Configure MySQL for local connections
echo "Configuring MySQL..."
mysql -u root -p'GymAnything#2024' -e "
    ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'GymAnything#2024';
    CREATE USER IF NOT EXISTS 'ga'@'localhost' IDENTIFIED BY 'password123';
    GRANT ALL PRIVILEGES ON *.* TO 'ga'@'localhost' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
" 2>/dev/null || echo "MySQL user configuration may need adjustment"

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "MySQL Server: $(mysql --version 2>/dev/null || echo 'installed')"
echo "MySQL Workbench: $(snap list mysql-workbench-community 2>/dev/null | tail -1 || echo 'installed via snap')"
echo ""
echo "MySQL credentials:"
echo "  Root: root / GymAnything#2024"
echo "  User: ga / password123"
echo ""
echo "MySQL Workbench will be configured in post_start hook"
