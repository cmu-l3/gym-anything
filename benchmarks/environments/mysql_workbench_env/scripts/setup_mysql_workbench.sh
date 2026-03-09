#!/bin/bash
# MySQL Workbench Setup Script (post_start hook)
# Configures MySQL Workbench and loads sample databases

echo "=== Setting up MySQL Workbench Environment ==="

# Wait for desktop to be ready
sleep 5

# Ensure MySQL is running
echo "Ensuring MySQL service is running..."
systemctl start mysql || true
sleep 2

# Wait for MySQL to be accessible
echo "Waiting for MySQL to be accessible..."
MYSQL_READY=false
for i in {1..30}; do
    if mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
        MYSQL_READY=true
        echo "MySQL is accessible after ${i}s"
        break
    fi
    sleep 1
done

if [ "$MYSQL_READY" = false ]; then
    echo "WARNING: MySQL may not be fully accessible"
fi

# Create working directories
echo "Creating working directories..."
mkdir -p /home/ga/Documents/databases
mkdir -p /home/ga/Documents/exports
mkdir -p /home/ga/Documents/sql_scripts
mkdir -p /home/ga/.mysql/workbench

# Download and install Sakila sample database (official MySQL sample database)
echo "Setting up Sakila sample database..."
cd /tmp

# Download Sakila database
if [ ! -f "/tmp/sakila-db.zip" ]; then
    echo "Downloading Sakila database..."
    wget -q "https://downloads.mysql.com/docs/sakila-db.zip" -O /tmp/sakila-db.zip 2>/dev/null || \
    wget -q "https://downloads.mysql.com/docs/sakila-db.tar.gz" -O /tmp/sakila-db.tar.gz 2>/dev/null || true
fi

# Extract and load Sakila
if [ -f "/tmp/sakila-db.zip" ]; then
    unzip -o /tmp/sakila-db.zip -d /tmp/ 2>/dev/null || true
    if [ -d "/tmp/sakila-db" ]; then
        echo "Loading Sakila schema..."
        mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-schema.sql 2>/dev/null || true
        echo "Loading Sakila data..."
        mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-data.sql 2>/dev/null || true
        echo "Sakila database loaded successfully"

        # Copy SQL files for reference
        cp /tmp/sakila-db/*.sql /home/ga/Documents/sql_scripts/ 2>/dev/null || true
    fi
elif [ -f "/tmp/sakila-db.tar.gz" ]; then
    tar -xzf /tmp/sakila-db.tar.gz -C /tmp/ 2>/dev/null || true
    if [ -d "/tmp/sakila-db" ]; then
        mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-schema.sql 2>/dev/null || true
        mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-data.sql 2>/dev/null || true
        cp /tmp/sakila-db/*.sql /home/ga/Documents/sql_scripts/ 2>/dev/null || true
    fi
fi

# Download and install World sample database
echo "Setting up World sample database..."
if [ ! -f "/tmp/world-db.zip" ]; then
    wget -q "https://downloads.mysql.com/docs/world-db.zip" -O /tmp/world-db.zip 2>/dev/null || true
fi

if [ -f "/tmp/world-db.zip" ]; then
    unzip -o /tmp/world-db.zip -d /tmp/ 2>/dev/null || true
    if [ -f "/tmp/world-db/world.sql" ]; then
        echo "Loading World database..."
        mysql -u root -p'GymAnything#2024' < /tmp/world-db/world.sql 2>/dev/null || true
        echo "World database loaded successfully"
        cp /tmp/world-db/*.sql /home/ga/Documents/sql_scripts/ 2>/dev/null || true
    fi
fi

# Verify databases are loaded
echo "Verifying databases..."
mysql -u root -p'GymAnything#2024' -e "SHOW DATABASES;" 2>/dev/null || true

# Grant privileges to ga user for all databases
mysql -u root -p'GymAnything#2024' -e "
    GRANT ALL PRIVILEGES ON sakila.* TO 'ga'@'localhost';
    GRANT ALL PRIVILEGES ON world.* TO 'ga'@'localhost';
    FLUSH PRIVILEGES;
" 2>/dev/null || true

# Set ownership for all directories
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/.mysql 2>/dev/null || true

# Create a MySQL Workbench desktop shortcut
cat > /home/ga/Desktop/MySQLWorkbench.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=MySQL Workbench
Comment=MySQL Database Design and Administration Tool
Exec=/snap/bin/mysql-workbench-community
Icon=/snap/mysql-workbench-community/current/usr/share/mysql-workbench/images/MySQLWorkbench.png
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;Database;
DESKTOPEOF
chmod +x /home/ga/Desktop/MySQLWorkbench.desktop
chown ga:ga /home/ga/Desktop/MySQLWorkbench.desktop

# Trust the desktop file (GNOME requires this)
su - ga -c "gio set /home/ga/Desktop/MySQLWorkbench.desktop metadata::trusted true" 2>/dev/null || true

# Create utility script to query MySQL databases
cat > /usr/local/bin/mysql-query << 'QUERYEOF'
#!/bin/bash
# Execute SQL query against MySQL database
# Usage: mysql-query "database" "SQL query"
DB="${1:-sakila}"
QUERY="$2"
mysql -u ga -ppassword123 "$DB" -e "$QUERY"
QUERYEOF
chmod +x /usr/local/bin/mysql-query

# Create sakila-specific query helper
cat > /usr/local/bin/sakila-query << 'QUERYEOF'
#!/bin/bash
# Execute SQL query against Sakila database
mysql -u ga -ppassword123 sakila -e "$1"
QUERYEOF
chmod +x /usr/local/bin/sakila-query

# Create world-specific query helper
cat > /usr/local/bin/world-query << 'QUERYEOF'
#!/bin/bash
# Execute SQL query against World database
mysql -u ga -ppassword123 world -e "$1"
QUERYEOF
chmod +x /usr/local/bin/world-query

# Create MySQL Workbench connections configuration directory
mkdir -p /home/ga/.mysql/workbench
chown -R ga:ga /home/ga/.mysql

# Start MySQL Workbench for the ga user
echo "Launching MySQL Workbench..."
su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"

# Wait for MySQL Workbench window to appear
sleep 10
WORKBENCH_STARTED=false
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "workbench\|mysql"; then
        WORKBENCH_STARTED=true
        echo "MySQL Workbench window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$WORKBENCH_STARTED" = true ]; then
    sleep 5

    # Maximize MySQL Workbench window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "workbench\|mysql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi

    # Dismiss any initial dialogs (welcome screen, etc.)
    echo "Dismissing any initial dialogs..."
    sleep 3

    # Press Escape to close any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true

    echo "Initial dialog handling complete"
else
    echo "WARNING: MySQL Workbench window not detected"
fi

echo ""
echo "=== MySQL Workbench Setup Complete ==="
echo ""
echo "MySQL Server Status: $(systemctl is-active mysql)"
echo ""
echo "Available Databases:"
mysql -u ga -ppassword123 -e "SHOW DATABASES;" 2>/dev/null || echo "Run 'mysql-query sakila \"SHOW TABLES;\"' to verify"
echo ""
echo "Sakila Database Info:"
echo "  - DVD rental store data (films, actors, customers, rentals)"
echo "  - Tables: actor, film, customer, rental, inventory, payment, etc."
echo ""
echo "World Database Info:"
echo "  - Countries and cities of the world"
echo "  - Tables: country, city, countrylanguage"
echo ""
echo "MySQL Credentials:"
echo "  User: ga"
echo "  Password: password123"
echo "  Host: localhost"
echo ""
echo "Quick query examples:"
echo "  sakila-query \"SELECT COUNT(*) FROM film;\""
echo "  world-query \"SELECT COUNT(*) FROM city;\""
