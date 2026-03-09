#!/bin/bash
# OpenSIS Environment Setup Script
# Uses the web-based installer (automated with Selenium) for proper installation.

echo "=== Setting up OpenSIS Environment ==="

# Log file for debugging
SETUP_LOG="/home/ga/env_setup_post_start.log"
exec > >(tee -a "$SETUP_LOG") 2>&1

OPENSIS_DIR="/var/www/html/opensis"

# ======= Start MariaDB Service =======
echo "Starting MariaDB service..."
systemctl start mariadb || systemctl start mysql || {
    echo "ERROR: Could not start database service"
    exit 1
}
systemctl enable mariadb 2>/dev/null || systemctl enable mysql 2>/dev/null || true

# Wait for MariaDB to be ready
wait_for_mariadb() {
    local timeout=60
    local elapsed=0
    echo "Waiting for MariaDB to be ready..."
    while [ $elapsed -lt $timeout ]; do
        if mysqladmin ping -h localhost --silent 2>/dev/null; then
            echo "MariaDB is ready!"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done
    echo "ERROR: MariaDB failed to start within $timeout seconds"
    return 1
}

wait_for_mariadb || exit 1

# ======= Configure Apache =======
echo "Configuring Apache for OpenSIS..."

# Create Apache virtual host configuration
cat > /etc/apache2/sites-available/opensis.conf << 'APACHE_CONF_EOF'
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    <Directory /var/www/html/opensis>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/opensis_error.log
    CustomLog ${APACHE_LOG_DIR}/opensis_access.log combined
</VirtualHost>
APACHE_CONF_EOF

# Enable the site and required modules
a2ensite opensis.conf 2>/dev/null || true
a2enmod rewrite 2>/dev/null || true
a2enmod headers 2>/dev/null || true

# ======= Start Apache Service =======
echo "Starting Apache service..."
systemctl start apache2
systemctl enable apache2

# Wait for Apache to be ready
wait_for_apache() {
    local timeout=30
    local elapsed=0
    echo "Waiting for Apache to be ready..."
    while [ $elapsed -lt $timeout ]; do
        if curl -s http://localhost/ >/dev/null 2>&1; then
            echo "Apache is ready!"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done
    echo "WARNING: Apache may not be fully ready"
    return 0
}

wait_for_apache

# ======= Set Permissions =======
echo "Setting file permissions..."
chown -R www-data:www-data "$OPENSIS_DIR"
chmod -R 755 "$OPENSIS_DIR"

# Make writable directories
for dir in assets tmp cache uploads files; do
    if [ -d "$OPENSIS_DIR/$dir" ]; then
        chmod -R 775 "$OPENSIS_DIR/$dir"
    fi
done

# ======= Check if OpenSIS is already configured =======
if [ -f "$OPENSIS_DIR/Data.php" ]; then
    echo "OpenSIS Data.php exists - checking if installation is complete..."

    # Try to verify installation by checking database
    DB_PASS=$(grep -o "DatabasePassword.*=.*'[^']*'" "$OPENSIS_DIR/Data.php" | sed "s/.*'\\([^']*\\)'.*/\\1/")
    DB_USER=$(grep -o "DatabaseUsername.*=.*'[^']*'" "$OPENSIS_DIR/Data.php" | sed "s/.*'\\([^']*\\)'.*/\\1/")
    DB_NAME=$(grep -o "DatabaseName.*=.*'[^']*'" "$OPENSIS_DIR/Data.php" | sed "s/.*'\\([^']*\\)'.*/\\1/")

    if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT COUNT(*) FROM login_authentication WHERE username='admin'" 2>/dev/null | grep -q "1"; then
        echo "OpenSIS is already properly installed!"
        SKIP_INSTALLER=true
    else
        echo "Data.php exists but installation seems incomplete. Removing to re-run installer..."
        rm -f "$OPENSIS_DIR/Data.php"
        SKIP_INSTALLER=false
    fi
else
    echo "No Data.php found - fresh installation needed."
    SKIP_INSTALLER=false
fi

# ======= Run Direct Database Setup =======
if [ "$SKIP_INSTALLER" != "true" ]; then
    echo "Running direct database setup..."

    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

    # Use direct_db_setup.sh if available
    if [ -f "$SCRIPT_DIR/direct_db_setup.sh" ]; then
        echo "Running direct database setup script..."
        bash "$SCRIPT_DIR/direct_db_setup.sh"
    else
        echo "Running inline database setup..."

        # MySQL command - check if sudo is needed
        MYSQL_CMD="mysql"
        if ! mysql -u root -e "SELECT 1" &>/dev/null; then
            MYSQL_CMD="sudo mysql"
        fi

        # Create database and user
        $MYSQL_CMD << 'MYSQL_SETUP_EOF'
DROP DATABASE IF EXISTS opensis;
CREATE DATABASE opensis CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'opensis_user'@'localhost' IDENTIFIED BY 'opensis_password_123';
GRANT ALL PRIVILEGES ON opensis.* TO 'opensis_user'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SETUP_EOF

        # Import schema
        $MYSQL_CMD opensis < "$OPENSIS_DIR/install/OpensisSchemaMysqlInc.sql" 2>/dev/null || true
        $MYSQL_CMD opensis < "$OPENSIS_DIR/install/OpensisProcsMysqlInc.sql" 2>/dev/null || true
        $MYSQL_CMD opensis < "$OPENSIS_DIR/install/OpensisTriggerMysqlInc.sql" 2>/dev/null || true

        # Generate password hash
        PASS_HASH=$(php -r 'include "/var/www/html/opensis/functions/PasswordHashFnc.php"; echo GenerateNewHash("Admin@123");' 2>/dev/null)
        [ -z "$PASS_HASH" ] && PASS_HASH=$(php -r 'echo password_hash("Admin@123", PASSWORD_BCRYPT);')

        # Insert essential data
        $MYSQL_CMD opensis << ESSENTIAL_DATA
INSERT INTO app (name, value) VALUES ('version', '9.2'), ('date', 'January 2025') ON DUPLICATE KEY UPDATE value=VALUES(value);
INSERT INTO user_profiles (id, profile, title) VALUES (1, 'admin', 'Administrator') ON DUPLICATE KEY UPDATE profile=VALUES(profile);
INSERT INTO schools (id, syear, title, address, city, state, zipcode, phone, reporting_gp_scale) VALUES (1, 2025, 'Demo School', '123 Main St', 'City', 'ST', '12345', '555-1234', 4.0) ON DUPLICATE KEY UPDATE title=VALUES(title);
INSERT INTO school_years (marking_period_id, syear, school_id, title, short_name, sort_order, start_date, end_date, does_grades, does_comments) VALUES (1, 2025, 1, '2024-2025', 'FY', 1, '2024-08-01', '2025-06-30', 'Y', 'Y') ON DUPLICATE KEY UPDATE title=VALUES(title);
INSERT INTO system_preference_misc (fail_count, activity_days, system_maintenance_switch) VALUES (5, 90, 'N') ON DUPLICATE KEY UPDATE fail_count=5;
INSERT INTO staff (staff_id, current_school_id, title, first_name, last_name, email, profile, profile_id) VALUES (1, 1, 'Mr.', 'Admin', 'User', 'admin@school.edu', 'admin', 1) ON DUPLICATE KEY UPDATE first_name=VALUES(first_name);
ALTER TABLE staff ADD COLUMN IF NOT EXISTS USER_ID int(11) DEFAULT NULL;
UPDATE staff SET USER_ID = 1, profile_id = 1 WHERE staff_id = 1;
INSERT INTO staff_school_info (staff_id, category, home_school, opensis_access, opensis_profile, school_access) VALUES (1, 'Administrator', 1, 'Y', 'admin', 'Y') ON DUPLICATE KEY UPDATE opensis_access='Y';
INSERT INTO login_authentication (user_id, profile_id, username, password, last_login, failed_login) VALUES (1, 1, 'admin', '$PASS_HASH', NOW(), 0) ON DUPLICATE KEY UPDATE password='$PASS_HASH', profile_id=1, failed_login=0;
INSERT INTO profile_exceptions (profile_id, modname, can_use, can_edit) VALUES (1, 'miscellaneous/Portal.php', 'Y', 'Y'), (1, 'students/Student.php', 'Y', 'Y'), (1, 'students/Student.php&include=GeneralInfoInc&student_id=new', 'Y', 'Y'), (1, 'students/Search.php', 'Y', 'Y') ON DUPLICATE KEY UPDATE can_use='Y';
INSERT INTO school_gradelevels (id, school_id, short_name, title, sort_order) VALUES (1, 1, '9', 'Grade 9', 1), (2, 1, '10', 'Grade 10', 2), (3, 1, '11', 'Grade 11', 3), (4, 1, '12', 'Grade 12', 4) ON DUPLICATE KEY UPDATE title=VALUES(title);
ESSENTIAL_DATA

        # Create Data.php
        cat > "$OPENSIS_DIR/Data.php" << 'DATAPHP_EOF'
<?php
$DatabaseType = 'mysqli';
$DatabaseServer = 'localhost';
$DatabaseUsername = 'opensis_user';
$DatabasePassword = 'opensis_password_123';
$DatabaseName = 'opensis';
$DatabasePort = '3306';
?>
DATAPHP_EOF
        chown www-data:www-data "$OPENSIS_DIR/Data.php"

        echo "Database setup complete"
    fi
fi

# ======= Setup Chrome for ga user =======
echo "Setting up Chrome for ga user..."

setup_user_chrome() {
    local username=$1
    local home_dir=$2

    echo "Setting up Chrome for user: $username"

    # Create Chrome config directory
    sudo -u $username mkdir -p "$home_dir/.config/google-chrome/Default"
    sudo -u $username mkdir -p "$home_dir/Downloads"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # Create Chrome preferences
    cat > "$home_dir/.config/google-chrome/Default/Preferences" << 'PREFEOF'
{
   "profile": {
      "default_content_setting_values": {
         "notifications": 2,
         "geolocation": 2
      },
      "password_manager_enabled": false
   },
   "browser": {
      "show_home_button": true,
      "check_default_browser": false
   },
   "download": {
      "prompt_for_download": false,
      "directory_upgrade": true
   },
   "safebrowsing": {
      "enabled": false
   },
   "credentials_enable_service": false,
   "translate": {
      "enabled": false
   }
}
PREFEOF
    chown $username:$username "$home_dir/.config/google-chrome/Default/Preferences"

    # Create desktop shortcut for OpenSIS
    cat > "$home_dir/Desktop/OpenSIS.desktop" << DESKTOPEOF
[Desktop Entry]
Name=OpenSIS
Comment=Student Information System
Exec=google-chrome-stable --no-sandbox --disable-gpu http://localhost/opensis
Icon=chromium-browser
StartupNotify=true
Terminal=false
Categories=Network;WebBrowser;Education;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/OpenSIS.desktop"
    chmod +x "$home_dir/Desktop/OpenSIS.desktop"

    # Create launch script
    cat > "$home_dir/launch_opensis.sh" << 'LAUNCHEOF'
#!/bin/bash
export DISPLAY=${DISPLAY:-:1}
xhost +local: 2>/dev/null || true

if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
elif command -v chrome-browser &> /dev/null; then
    CHROME_CMD="chrome-browser"
else
    echo "ERROR: No Chrome/Chromium browser found!"
    exit 1
fi

$CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --disable-background-networking \
    --disable-sync \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --window-size=1920,1080 \
    --force-device-scale-factor=1 \
    --disable-infobars \
    --password-store=basic \
    "http://localhost/opensis" > /tmp/chrome_opensis.log 2>&1 &

echo "Chrome started with OpenSIS"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_opensis.sh"
    chmod +x "$home_dir/launch_opensis.sh"
}

# Setup for ga user
if id "ga" &>/dev/null; then
    setup_user_chrome "ga" "/home/ga"
fi

# ======= Create verification helper script =======
echo "Creating verification helper script..."

cat > /usr/local/bin/opensis-db-query << 'DBQUERYEOF'
#!/bin/bash
# Helper script to query OpenSIS database for verification
# Usage: opensis-db-query "SELECT * FROM students WHERE ..."

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$1" 2>/dev/null
DBQUERYEOF
chmod +x /usr/local/bin/opensis-db-query

# Also create one for root user (installer uses root)
cat > /usr/local/bin/opensis-db-query-root << 'DBQUERYEOF'
#!/bin/bash
mysql -u root opensis -e "$1" 2>/dev/null
DBQUERYEOF
chmod +x /usr/local/bin/opensis-db-query-root

# ======= Launch Chrome with OpenSIS =======
echo "Launching Chrome with OpenSIS homepage..."
su - ga -c "DISPLAY=:1 /home/ga/launch_opensis.sh" || true
sleep 3

echo "=== OpenSIS setup completed ==="
echo ""
echo "Access OpenSIS at: http://localhost/opensis"
echo ""
echo "Credentials (if installed via automation):"
echo "  Username: admin"
echo "  Password: Admin@123"
echo ""
echo "To verify database connection:"
echo "  opensis-db-query 'SELECT * FROM students LIMIT 5'"
