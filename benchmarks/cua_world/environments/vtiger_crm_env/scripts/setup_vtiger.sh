#!/bin/bash
set -e

echo "=== Setting up Vtiger CRM ==="

# Wait for desktop to be ready
sleep 5

# ---------------------------------------------------------------
# 1. Prepare Vtiger directory and configuration
# ---------------------------------------------------------------
echo "--- Preparing Vtiger configuration ---"
mkdir -p /home/ga/vtiger/docker
cp /workspace/config/docker-compose.yml /home/ga/vtiger/
cp /workspace/config/Dockerfile /home/ga/vtiger/docker/
cp /workspace/config/entrypoint.sh /home/ga/vtiger/docker/
chown -R ga:ga /home/ga/vtiger

# ---------------------------------------------------------------
# 2. Start Docker containers
# ---------------------------------------------------------------
echo "--- Starting Docker containers ---"
cd /home/ga/vtiger
docker compose build --no-cache
docker compose up -d

# Wait for MariaDB to be ready
echo "--- Waiting for MariaDB ---"
wait_for_mysql() {
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker exec vtiger-db mysqladmin ping -h localhost -u root -proot_pass 2>/dev/null | grep -q "alive"; then
            echo "MariaDB is ready (${elapsed}s)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "MariaDB timeout after ${timeout}s"
    return 1
}
wait_for_mysql

# ---------------------------------------------------------------
# 3. Wait for Vtiger to be accessible
# ---------------------------------------------------------------
echo "--- Waiting for Vtiger application ---"
wait_for_vtiger() {
    local timeout=180
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/ 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "Vtiger is ready (HTTP $HTTP_CODE) (${elapsed}s)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... (${elapsed}s, HTTP $HTTP_CODE)"
    done
    echo "Vtiger timeout after ${timeout}s"
    return 1
}
wait_for_vtiger

# ---------------------------------------------------------------
# 4. Create config.inc.php from template
# ---------------------------------------------------------------
echo "--- Creating Vtiger config.inc.php ---"

# Generate application unique key
APP_KEY=$(docker exec vtiger-app php -r "echo md5(microtime());" 2>/dev/null)

cat > /tmp/create_vtiger_config.sh << 'CFGEOF'
#!/bin/bash
set -e
cd /var/www/html/vtigercrm

# Create config.inc.php from template
cp config.template.php config.inc.php

# Substitute all template variables
sed -i "s|_DBC_SERVER_|vtiger-db|g" config.inc.php
sed -i "s|_DBC_PORT_|3306|g" config.inc.php
sed -i "s|_DBC_USER_|vtiger|g" config.inc.php
sed -i "s|_DBC_PASS_|vtiger_pass|g" config.inc.php
sed -i "s|_DBC_NAME_|vtiger|g" config.inc.php
sed -i "s|_DBC_TYPE_|mysqli|g" config.inc.php
sed -i "s|_DB_STAT_|true|g" config.inc.php
sed -i "s|_SITE_URL_|http://localhost:8000|g" config.inc.php
sed -i "s|_VT_CHARSET_|UTF-8|g" config.inc.php
sed -i "s|_DEFAULT_LANGUAGE_|en_us|g" config.inc.php
sed -i "s|_USER_ADMIN_EMAIL_|admin@vtiger.local|g" config.inc.php
sed -i "s|_USER_SUPPORT_EMAIL_|support@vtiger.local|g" config.inc.php
CFGEOF
# Append the dynamic APP_KEY
echo "sed -i \"s|_VT_APP_UNIQUE_KEY_|${APP_KEY}|g\" config.inc.php" >> /tmp/create_vtiger_config.sh
cat >> /tmp/create_vtiger_config.sh << 'CFGEOF2'

# Fix directory paths
VTIGER_DIR=$(pwd)/
sed -i "s|_VT_ROOTDIR_|${VTIGER_DIR}|g" config.inc.php
sed -i "s|_VT_CACHEDIR_|cache/|g" config.inc.php
sed -i "s|_VT_TMPDIR_|cache/upload/|g" config.inc.php
sed -i "s|_VT_STORAGEDIR_|storage/|g" config.inc.php
sed -i "s|_VT_UPLOADMAXSIZE_|3000000|g" config.inc.php
sed -i "s|_VT_CURL_TIMEOUT_|30|g" config.inc.php

# Fix abort flags
sed -i "s|_ABORTONDBMISMATCH_|true|g" config.inc.php
sed -i "s|_ABORTONDBNONUTF8_|true|g" config.inc.php
sed -i "s|_ABORTONMYSQLSTRICT_|true|g" config.inc.php
sed -i "s|_ABORTONINVALIDXML_|true|g" config.inc.php
sed -i "s|_ABORTONINVALIDHTTPSREFERER_|true|g" config.inc.php

chown www-data:www-data config.inc.php
chmod 775 config.inc.php
echo "Config file created successfully."
CFGEOF2

docker cp /tmp/create_vtiger_config.sh vtiger-app:/tmp/create_vtiger_config.sh
docker exec vtiger-app bash /tmp/create_vtiger_config.sh 2>&1

# ---------------------------------------------------------------
# 5. Run Vtiger schema installation via PHP CLI
# ---------------------------------------------------------------
echo "--- Installing Vtiger schema (this takes 1-2 minutes) ---"

cat > /tmp/vtiger_cli_install.php << 'PHPEOF'
<?php
// CLI Installer for Vtiger CRM - mimics Step7 of the web wizard
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
set_time_limit(0);
ini_set('memory_limit', '512M');

chdir('/var/www/html/vtigercrm');

// Set up session data that the installer expects
$_SESSION = array();
$_SESSION['config_file_info'] = array(
    'db_hostname' => 'vtiger-db',
    'db_username' => 'vtiger',
    'db_password' => 'vtiger_pass',
    'db_name' => 'vtiger',
    'db_type' => 'mysqli',
    'root_directory' => '/var/www/html/vtigercrm/',
    'site_URL' => 'http://localhost:8000',
    'admin_email' => 'admin@vtiger.local',
    'currency_name' => 'US Dollar',
    'currency_code' => 'USD',
    'currency_symbol' => '$',
    'default_language' => 'en_us',
    'timezone' => 'UTC',
    'password' => 'password',
    'firstname' => 'Admin',
    'lastname' => 'User',
    'authentication_key' => md5(microtime()),
);
$_SESSION['vtiger_version'] = '8.3.0';

// Fake SERVER variables the framework might need
$_SERVER['HTTP_HOST'] = 'localhost:8000';
$_SERVER['REQUEST_URI'] = '/index.php';
$_SERVER['SERVER_NAME'] = 'localhost';
$_SERVER['SERVER_PORT'] = '8000';
$_SERVER['DOCUMENT_ROOT'] = '/var/www/html/vtigercrm';

echo "Loading Vtiger framework...\n";
require_once('vendor/autoload.php');
include_once('config.inc.php');
include_once('vtigerversion.php');
include_once('vtlib/Vtiger/Utils.php');
include_once('include/utils/utils.php');
include_once('include/Loader.php');
vimport('includes.runtime.EntryPoint');

echo "Connecting to database...\n";
global $adb;
$adb = PearDatabase::getInstance();
$adb->connect();
$adb->query('SET NAMES utf8');

echo "Initializing schema...\n";
vimport('~~modules/Install/models/InitSchema.php');
Install_InitSchema_Model::initialize();

echo "Installing modules...\n";
vimport('~~modules/Install/models/Utils.php');
Install_Utils_Model::installModules();

echo "Running migrations...\n";
Install_InitSchema_Model::upgrade();

// Fix admin password using crypt() with first 2 chars of username as salt
$salt = substr('admin', 0, 2);
$correctHash = crypt('password', $salt);
$adb->pquery("UPDATE vtiger_users SET user_password = ?, crypt_type = 'SHA256' WHERE user_name = 'admin'", array($correctHash));

$result = $adb->pquery("SHOW TABLES", array());
$tableCount = $adb->num_rows($result);
echo "Installation complete! Tables: $tableCount\n";
?>
PHPEOF

docker cp /tmp/vtiger_cli_install.php vtiger-app:/tmp/vtiger_cli_install.php
docker exec vtiger-app php /tmp/vtiger_cli_install.php 2>&1 | grep -E "^(Loading|Connecting|Initializing|Installing|Running|Installation)" || true
echo "  Schema installation done"

# Restart Apache to pick up new config
docker exec vtiger-app apache2ctl restart 2>/dev/null || true
sleep 3

# Fix cache/storage/logs/templates permissions (required for Vtiger to serve pages)
docker exec vtiger-app bash -c "
  mkdir -p /var/www/html/vtigercrm/cache/logs
  chmod -R 777 /var/www/html/vtigercrm/cache
  chmod -R 777 /var/www/html/vtigercrm/storage
  chmod -R 777 /var/www/html/vtigercrm/test
  chmod -R 777 /var/www/html/vtigercrm/logs 2>/dev/null
  chmod 775 /var/www/html/vtigercrm/config.inc.php
" 2>/dev/null || true

# Verify login page loads
LOGIN_CHECK=$(curl -s http://localhost:8000/ 2>/dev/null | grep -c "Sign in" || echo "0")
if [ "$LOGIN_CHECK" -gt 0 ]; then
    echo "  Login page verified OK"
else
    echo "  WARNING: Login page check failed"
fi

# ---------------------------------------------------------------
# 6. Seed realistic CRM data
# ---------------------------------------------------------------
echo "--- Seeding CRM data ---"

# Run the PHP-based data seeder
cp /workspace/utils/seed_data.php /tmp/seed_data.php
docker cp /tmp/seed_data.php vtiger-app:/tmp/seed_data.php
docker exec vtiger-app php /tmp/seed_data.php 2>&1 | tail -5 || true
echo "  Data seeding complete"

# ---------------------------------------------------------------
# 7. Verify data was loaded
# ---------------------------------------------------------------
echo "--- Verifying seeded data ---"
CONTACT_COUNT=$(docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -N -e "SELECT COUNT(*) FROM vtiger_contactdetails" 2>/dev/null || echo "0")
ORG_COUNT=$(docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -N -e "SELECT COUNT(*) FROM vtiger_account" 2>/dev/null || echo "0")
echo "  Contacts: $CONTACT_COUNT"
echo "  Organizations: $ORG_COUNT"

# ---------------------------------------------------------------
# 8. Create database query helper
# ---------------------------------------------------------------
echo "--- Creating database query helper ---"
cat > /usr/local/bin/vtiger-db-query << 'DBEOF'
#!/bin/bash
# Execute SQL query against Vtiger CRM database
docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -N -e "$1" 2>/dev/null
DBEOF
chmod +x /usr/local/bin/vtiger-db-query

# ---------------------------------------------------------------
# 9. Setup Firefox
# ---------------------------------------------------------------
echo "--- Setting up Firefox ---"

# Warm-up launch to create default profile
su - ga -c "DISPLAY=:1 firefox --headless &"
sleep 8
pkill -f firefox || true
sleep 2

# Find default profile directory (snap Firefox)
SNAP_PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
if [ -z "$SNAP_PROFILE_DIR" ]; then
    SNAP_PROFILE_DIR=$(find /home/ga/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
fi

if [ -n "$SNAP_PROFILE_DIR" ]; then
    echo "  Found Firefox profile at: $SNAP_PROFILE_DIR"
    cat > "$SNAP_PROFILE_DIR/user.js" << 'FFEOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.homepage", "http://localhost:8000");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.page", 1);
user_pref("signon.rememberSignons", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("browser.feeds.showFirstRunUI", false);
user_pref("browser.uitour.enabled", false);
FFEOF
    chown ga:ga "$SNAP_PROFILE_DIR/user.js"
else
    echo "  WARNING: Could not find Firefox default profile directory"
fi

# Create desktop shortcut
cat > /home/ga/Desktop/VtigerCRM.desktop << 'DSKEOF'
[Desktop Entry]
Name=Vtiger CRM
Comment=Customer Relationship Management
Exec=firefox http://localhost:8000
Icon=firefox
Terminal=false
Type=Application
Categories=Network;WebBrowser;
DSKEOF
chmod +x /home/ga/Desktop/VtigerCRM.desktop
chown ga:ga /home/ga/Desktop/VtigerCRM.desktop

# ---------------------------------------------------------------
# 10. Launch Firefox and perform initial login
# ---------------------------------------------------------------
echo "--- Launching Firefox ---"
su - ga -c "DISPLAY=:1 firefox http://localhost:8000/ &"

# Wait for Firefox window to appear
echo "--- Waiting for Firefox window ---"
FIREFOX_TIMEOUT=60
FIREFOX_ELAPSED=0
while [ $FIREFOX_ELAPSED -lt $FIREFOX_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iq "firefox\|vtiger\|mozilla"; then
        echo "Firefox window detected (${FIREFOX_ELAPSED}s)"
        break
    fi
    sleep 3
    FIREFOX_ELAPSED=$((FIREFOX_ELAPSED + 3))
done

# Maximize Firefox window
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# ---------------------------------------------------------------
# 11. Auto-login to Vtiger (coordinates at 1920x1080)
# ---------------------------------------------------------------
echo "--- Logging into Vtiger ---"

# Wait extra for Firefox to fully render the login page (JS-heavy)
sleep 12

# Coordinates at 1920x1080 (scaled from 1280x720 visual_grounding coords)
# Username: (309, 269) -> (464, 404)
# Password: use Tab for reliability
# Sign In: (309, 384) -> (464, 576)

# Click username field
DISPLAY=:1 xdotool mousemove 464 404
sleep 0.3
DISPLAY=:1 xdotool click 1
sleep 0.5
DISPLAY=:1 xdotool type --delay 30 "admin"
sleep 0.3

# Tab to password field (more reliable than clicking)
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type --delay 30 "password"
sleep 0.3

# Press Enter to submit (more reliable than clicking Sign In)
DISPLAY=:1 xdotool key Return
sleep 8

# After first login, Vtiger redirects to SystemSetup page
# Navigate to dashboard to complete first-run
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.2
DISPLAY=:1 xdotool type --delay 20 "http://localhost:8000/index.php"
DISPLAY=:1 xdotool key Return
sleep 5

echo "=== Vtiger CRM setup complete ==="
echo "  URL: http://localhost:8000"
echo "  Admin: admin / password"
