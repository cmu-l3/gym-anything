#!/bin/bash
# Do NOT use set -e: individual failures should not abort the entire setup
echo "=== Setting up OpenCAD ==="

sleep 5

# ------------------------------------------------------------------
# 1. Start database with Docker Compose
# ------------------------------------------------------------------
mkdir -p /home/ga/opencad
cp /workspace/config/docker-compose.yml /home/ga/opencad/docker-compose.yml

cd /home/ga/opencad
docker-compose up -d

# ------------------------------------------------------------------
# 2. Wait for MySQL to be ready
# ------------------------------------------------------------------
echo "=== Waiting for MySQL ==="
wait_for_mysql() {
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker exec opencad-db mysqladmin ping -h localhost -u root -prootpass 2>/dev/null; then
            echo "MySQL is ready"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "MySQL timeout after ${timeout}s"
    return 1
}
wait_for_mysql || true

# Extra wait for init scripts to complete
sleep 10

# Verify database and tables exist
echo "=== Verifying database ==="
docker exec opencad-db mysql -u root -prootpass -e "USE opencad; SHOW TABLES;" 2>/dev/null || {
    echo "Database verification failed, waiting more..."
    sleep 15
    docker exec opencad-db mysql -u root -prootpass -e "USE opencad; SHOW TABLES;" 2>/dev/null || true
}

# Grant all privileges to opencad user
docker exec opencad-db mysql -u root -prootpass -e "GRANT ALL PRIVILEGES ON opencad.* TO 'opencad'@'%' IDENTIFIED BY 'opencadpass'; FLUSH PRIVILEGES;" 2>/dev/null || true

# ------------------------------------------------------------------
# 2b. Import official OpenCAD schema and game data
# ------------------------------------------------------------------
echo "=== Importing official OpenCAD schema ==="
# Replace DB_PREFIX placeholder and import
sed 's/<DB_PREFIX>//g' /opt/opencad-src/sql/oc_install.sql > /tmp/oc_install.sql
cat /tmp/oc_install.sql | docker exec -i opencad-db mysql -u root -prootpass opencad

# Import GTAV game data
echo "=== Importing GTAV game data ==="
sed 's/<DB_PREFIX>//g' /opt/opencad-src/sql/game_data/GTAV/oc_GTAV_data.sql > /tmp/oc_gtav_data.sql
cat /tmp/oc_gtav_data.sql | docker exec -i opencad-db mysql -u root -prootpass opencad

# Import custom seed data (NCIC data, civilians, etc.)
echo "=== Importing seed data ==="
cat /workspace/data/seed_data.sql | docker exec -i opencad-db mysql -u root -prootpass opencad

# ------------------------------------------------------------------
# 2c. Add extended columns/tables needed by tasks
# ------------------------------------------------------------------
echo "=== Adding extended schema for task support ==="
docker exec opencad-db mysql -u root -prootpass opencad -e "
ALTER TABLE ncic_arrests ADD COLUMN narrative TEXT DEFAULT NULL;
ALTER TABLE ncic_warnings ADD COLUMN remarks TEXT DEFAULT NULL;
CREATE TABLE IF NOT EXISTS reports (
  id INT(11) NOT NULL AUTO_INCREMENT,
  title VARCHAR(255) DEFAULT NULL,
  narrative TEXT DEFAULT NULL,
  date DATE DEFAULT NULL,
  type VARCHAR(100) DEFAULT NULL,
  created_by VARCHAR(255) DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
);
" 2>/dev/null || true

# Verify import
TABLE_COUNT=$(docker exec opencad-db mysql -u root -prootpass opencad -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='opencad';" 2>/dev/null)
echo "Tables created: $TABLE_COUNT"

USER_COUNT=$(docker exec opencad-db mysql -u root -prootpass opencad -N -e "SELECT COUNT(*) FROM users;" 2>/dev/null)
echo "Users in database: $USER_COUNT"

# ------------------------------------------------------------------
# 3. Set up OpenCAD PHP app in the container
# ------------------------------------------------------------------
echo "=== Configuring OpenCAD PHP application ==="

# Install PHP MySQL extension inside the container first
docker exec opencad-app bash -c "docker-php-ext-install mysqli pdo pdo_mysql" || true

# Copy source files into the PHP container (after extension install)
docker cp /opt/opencad-src/. opencad-app:/var/www/html/

# Configure the database connection and settings
docker exec opencad-app bash -c "cat > /var/www/html/oc-config.php << 'PHPEOF'
<?php
/**
 * OpenCAD Configuration File
 */

// Community Name
define('COMMUNITY_NAME', 'San Andreas Emergency Services');
define('DEFAULT_LANGUAGE', 'en');
define('DEFAULT_LANGUAGE_DIRECTION', 'ltr');

// Database Configuration
define('DB_HOST', 'opencad-db');
define('DB_NAME', 'opencad');
define('DB_USER', 'opencad');
define('DB_PASSWORD', 'opencadpass');
define('DB_PREFIX', '');

// Base URL
define('BASE_URL', 'http://localhost');

// API Security
define('ENABLE_API_SECURITY', false);

// Email Settings
define('CAD_FROM_EMAIL', 'noreply@opencad.local');
define('CAD_FROM_NAME', 'OpenCAD System');
define('CAD_TO_EMAIL', 'admin@opencad.local');
define('CAD_TO_NAME', 'OpenCAD Admin');

// Security Keys
define('AUTH_KEY',         'opencad-auth-key-2024');
define('SECURE_AUTH_KEY',  'opencad-secure-auth-2024');
define('LOGGED_IN_KEY',    'opencad-logged-in-2024');
define('NONCE_KEY',        'opencad-nonce-2024');
define('AUTH_SALT',        'opencad-auth-salt-2024');
define('SECURE_AUTH_SALT', 'opencad-secure-salt-2024');
define('LOGGED_IN_SALT',   'opencad-login-salt-2024');
define('NONCE_SALT',       'opencad-nonce-salt-2024');
define('COOKIE_NAME',      'opencad_session');

// Department Features - Police
define('POLICE_NCIC_NAME', true);
define('POLICE_NCIC_PLATE', true);
define('POLICE_BOLO', true);
define('POLICE_PANIC', true);
define('POLICE_CALL_SELFASSIGN', true);

// Department Features - Fire
define('FIRE_PANIC', true);
define('FIRE_BOLO', true);
define('FIRE_NCIC_NAME', false);
define('FIRE_NCIC_PLATE', false);
define('FIRE_CALL_SELFASSIGN', true);

// Department Features - EMS
define('EMS_PANIC', true);
define('EMS_BOLO', true);
define('EMS_NCIC_NAME', false);
define('EMS_NCIC_PLATE', false);
define('EMS_CALL_SELFASSIGN', true);

// Department Features - Roadside
define('ROADSIDE_PANIC', false);
define('ROADSIDE_BOLO', false);
define('ROADSIDE_NCIC_NAME', false);
define('ROADSIDE_NCIC_PLATE', false);
define('ROADSIDE_CALL_SELFASSIGN', true);

// Civilian Features
define('CIV_WARRANT', true);
define('CIV_REG', true);
define('CIV_LIMIT_MAX_IDENTITIES', 5);
define('CIV_LIMIT_MAX_VEHICLES', 8);
define('CIV_LIMIT_MAX_WEAPONS', 10);

// Moderator Permissions
define('MODERATOR_APPROVE_USER', true);
define('MODERATOR_EDIT_USER', true);
define('MODERATOR_SUSPEND_WITH_REASON', true);
define('MODERATOR_SUSPEND_WITHOUT_REASON', true);
define('MODERATOR_REACTIVATE_USER', true);
define('MODERATOR_REMOVE_GROUP', true);
define('MODERATOR_DELETE_USER', true);
define('MODERATOR_NCIC_EDITOR', true);
define('MODERATOR_DATA_MANAGER', true);
define('MODERATOR_DATAMAN_CITATIONTYPES', true);
define('MODERATOR_DATAMAN_DEPARTMENTS', true);
define('MODERATOR_DATAMAN_INCIDENTTYPES', true);
define('MODERATOR_DATAMAN_RADIOCODES', true);
define('MODERATOR_DATAMAN_STREETS', true);
define('MODERATOR_DATAMAN_VEHICLES', true);
define('MODERATOR_DATAMAN_WARNINGTYPES', true);
define('MODERATOR_DATAMAN_WARRANTTYPES', true);
define('MODERATOR_DATAMAN_WEAPONS', true);
define('MODERATOR_DATAMAN_IMPEXPRES', true);

// System Settings
define('DEMO_MODE', false);
define('USE_GRAVATAR', false);
define('OC_DEBUG', false);

// Absolute Path
if (!defined('ABSPATH'))
    define('ABSPATH', dirname(__FILE__) . '/');

// Load functions
\$_NOLOAD = isset(\$_NOLOAD) ? \$_NOLOAD : false;
if (!\$_NOLOAD) {
    require_once(ABSPATH . 'oc-functions.php');
}
PHPEOF"

# Fix permissions
docker exec opencad-app bash -c "chown -R www-data:www-data /var/www/html && chmod -R 755 /var/www/html"

# Remove install directory to skip installer
docker exec opencad-app bash -c "rm -rf /var/www/html/oc-install"

# Restart Apache in the PHP container to pick up PHP extensions and new files
docker exec opencad-app bash -c "apache2ctl graceful" || true
sleep 5

# ------------------------------------------------------------------
# 3b. Create users with proper bcrypt passwords using PHP
# ------------------------------------------------------------------
echo "=== Creating users with bcrypt passwords ==="
docker exec opencad-app php -r '
$pdo = new PDO("mysql:host=opencad-db;dbname=opencad", "opencad", "opencadpass");
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$hash = password_hash("Admin123!", PASSWORD_DEFAULT);
$stmt = $pdo->prepare("INSERT INTO users (name, email, password, identifier, admin_privilege, supervisor_privilege, password_reset, approved) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
$stmt->execute(["Admin User", "admin@opencad.local", $hash, "1A-01", 3, 1, 0, 1]);
$stmt->execute(["Dispatch Officer", "dispatch@opencad.local", $hash, "DISP-01", 1, 0, 0, 1]);
$hash2 = password_hash("password123", PASSWORD_DEFAULT);
$stmt->execute(["Sarah Mitchell", "sarah.mitchell@opencad.local", $hash2, "3A-15", 1, 0, 0, 0]);
$stmt->execute(["James Rodriguez", "james.rodriguez@opencad.local", $hash2, "4B-22", 1, 0, 0, 0]);
echo "Users created\n";
'

# Verify users
USER_COUNT=$(docker exec opencad-db mysql -u root -prootpass opencad -N -e "SELECT COUNT(*) FROM users;" 2>/dev/null)
echo "Users in database after PHP insert: $USER_COUNT"

# ------------------------------------------------------------------
# 3c. Assign users to departments (required for CAD/dispatch access)
# ------------------------------------------------------------------
echo "=== Assigning department access ==="
# Department IDs: 1=Communications(Dispatch), 2=State, 3=Highway, 4=Sheriff, 5=Police, 6=Fire, 7=EMS, 8=Civilian, 9=Roadside
# Admin user (ID 2) gets Communications (dispatch) + Police + Civilian access
# Dispatch Officer (ID 3) gets Communications (dispatch) access
docker exec opencad-db mysql -u root -prootpass opencad -e "
INSERT INTO user_departments (user_id, department_id) VALUES (2, 1), (2, 5), (2, 8), (3, 1);
INSERT INTO user_departments_temp (user_id, department_id) VALUES (2, 1), (2, 5), (2, 8), (3, 1);
" 2>/dev/null || true

# Sarah Mitchell (ID 4) requested Police department access during registration
# This goes into user_departments_temp so the approve action copies it to user_departments
docker exec opencad-db mysql -u root -prootpass opencad -e "
INSERT INTO user_departments_temp (user_id, department_id) VALUES (4, 5);
" 2>/dev/null || true
echo "Department assignments complete"

# ------------------------------------------------------------------
# 4. Wait for OpenCAD web interface to be accessible
# ------------------------------------------------------------------
echo "=== Waiting for OpenCAD web interface ==="
for i in $(seq 1 36); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "OpenCAD web interface is ready (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting for web interface... attempt $i (HTTP $HTTP_CODE)"
    sleep 5
done

# ------------------------------------------------------------------
# 5. Set up Firefox profile
# ------------------------------------------------------------------
echo "=== Configuring Firefox ==="

PROFILE_DIR="/home/ga/.mozilla/firefox/default-release"
mkdir -p "$PROFILE_DIR"

cat > "$PROFILE_DIR/user.js" << 'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.policy.firstRunURL", "");
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.homepage", "http://localhost/index.php");
user_pref("browser.startup.page", 1);
user_pref("browser.rights.3.shown", true);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("sidebar.main.tools", "");
user_pref("sidebar.nimbus", "");
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.enabled", false);
user_pref("extensions.getAddons.showPane", false);
user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);
user_pref("browser.discovery.enabled", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("startup.homepage_override_url", "");
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.sessionstore.max_resumed_crashes", 0);
EOF

cat > /home/ga/.mozilla/firefox/profiles.ini << 'EOF'
[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

chown -R ga:ga /home/ga/.mozilla

# ------------------------------------------------------------------
# 6. Launch Firefox (snap-aware: launch→kill→configure→relaunch)
# ------------------------------------------------------------------
echo "=== Launching Firefox (first launch to create snap profile) ==="
su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php' &"
sleep 8

# Kill first instance so we can configure snap profile
pkill -f firefox || true
sleep 3

# Copy user.js to snap Firefox profile directory (created by first launch)
SNAP_PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
if [ -d "$SNAP_PROFILE_DIR" ]; then
    # Find the default-release profile in snap dir
    SNAP_DEFAULT=$(find "$SNAP_PROFILE_DIR" -maxdepth 1 -type d -name '*default-release*' | head -1)
    if [ -z "$SNAP_DEFAULT" ]; then
        SNAP_DEFAULT="$SNAP_PROFILE_DIR/default-release"
        mkdir -p "$SNAP_DEFAULT"
    fi
    cp "$PROFILE_DIR/user.js" "$SNAP_DEFAULT/user.js"
    chown -R ga:ga "$SNAP_PROFILE_DIR"
    echo "Copied user.js to snap profile: $SNAP_DEFAULT"
fi

# Relaunch Firefox with configured profile
echo "=== Relaunching Firefox ==="
su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php' &"
sleep 8

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

sleep 2

echo "=== OpenCAD setup complete ==="
echo "Login credentials: admin@opencad.local / Admin123!"
echo "Web URL: http://localhost/"
