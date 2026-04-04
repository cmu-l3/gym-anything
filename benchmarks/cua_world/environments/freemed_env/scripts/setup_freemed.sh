#!/bin/bash
# FreeMED Setup Script (post_start hook)
# Installs FreeMED from GitHub source using LAMP stack
# FreeMED URL: http://localhost/freemed/
# Admin credentials: admin / admin
# Uses Dojo UI (PHP 7.4 compatible; GWT UI requires Java compilation)

set -e

echo "=== Setting up FreeMED via LAMP ==="

FREEMED_URL="http://localhost/freemed/"
FREEMED_DIR="/usr/share/freemed"
FREEMED_DB="freemed"
FREEMED_DB_USER="freemed"
FREEMED_DB_PASS="freemed"
FREEMED_ADMIN_USER="admin"
FREEMED_ADMIN_PASS="admin"

# -----------------------------------------------------------------------
# Start services
# -----------------------------------------------------------------------
echo "Starting MySQL and Apache..."
systemctl enable mysql apache2 2>/dev/null || true
systemctl start mysql || service mysql start
systemctl start apache2 || service apache2 start
sleep 3

# -----------------------------------------------------------------------
# Configure MySQL
# -----------------------------------------------------------------------
echo "Configuring MySQL..."

# Allow stored procedures with binary logging
mysql -e "SET GLOBAL log_bin_trust_function_creators = 1;" 2>/dev/null || true

# Create FreeMED database and user
mysql -e "CREATE DATABASE IF NOT EXISTS ${FREEMED_DB} DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;" 2>/dev/null
mysql -e "CREATE USER IF NOT EXISTS '${FREEMED_DB_USER}'@'localhost' IDENTIFIED BY '${FREEMED_DB_PASS}';" 2>/dev/null
mysql -e "GRANT ALL PRIVILEGES ON ${FREEMED_DB}.* TO '${FREEMED_DB_USER}'@'localhost';" 2>/dev/null
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null

echo "MySQL configured"

# -----------------------------------------------------------------------
# Clone FreeMED from GitHub
# -----------------------------------------------------------------------
echo "Installing FreeMED from GitHub..."
if [ ! -d "$FREEMED_DIR" ]; then
    git clone --depth=1 https://github.com/freemed/freemed.git "$FREEMED_DIR" 2>&1 | tail -3
else
    echo "FreeMED already cloned at $FREEMED_DIR"
fi

# -----------------------------------------------------------------------
# Apply PHP 7.4 compatibility fix
# FreeMED's API.php unconditionally declares get_magic_quotes_runtime()
# which conflicts with PHP 7.4's built-in (deprecated) function.
# -----------------------------------------------------------------------
echo "Applying PHP 7.4 compatibility fix..."
python3 -c "
import re
with open('${FREEMED_DIR}/lib/API.php', 'r') as f:
    content = f.read()
# Wrap function declarations in function_exists checks
old = 'function get_magic_quotes_runtime() { return false; }\nfunction define_syslog_variables() { return false; }'
new = 'if (!function_exists(\"get_magic_quotes_runtime\")) { function get_magic_quotes_runtime() { return false; } }\nif (!function_exists(\"define_syslog_variables\")) { function define_syslog_variables() { return false; } }'
content = content.replace(old, new)
with open('${FREEMED_DIR}/lib/API.php', 'w') as f:
    f.write(content)
print('API.php patched')
" 2>/dev/null || echo "API.php patch skipped (already patched or not needed)"
# -----------------------------------------------------------------------
# Fix PHP Warning in freemed.php:180 (non-numeric value encountered)
# ($_REQUEST['_f'] + 0) causes PHP Warning when facility value is non-numeric
# (e.g., empty string from login form). Replace with intval() for proper cast.
# This warning can corrupt JSON API responses if display_errors is On.
# -----------------------------------------------------------------------
echo "Fixing freemed.php:180 non-numeric PHP warning..."
python3 -c "
with open('${FREEMED_DIR}/lib/freemed.php', 'r') as f:
    content = f.read()
old = \"( \\\$_REQUEST['_f'] + 0 )\"
new = \"intval( \\\$_REQUEST['_f'] )\"
if old in content:
    content = content.replace(old, new)
    with open('${FREEMED_DIR}/lib/freemed.php', 'w') as f:
        f.write(content)
    print('freemed.php:180 fixed: replaced non-numeric cast with intval()')
else:
    print('freemed.php:180 already fixed or pattern not found')
" 2>/dev/null || echo "freemed.php fix skipped"


# -----------------------------------------------------------------------
# Fix Smarty PHP Parse error in encounterconsole.tpl
# An empty {t}...{/t} block inside a label="" HTML attribute AND inside an
# HTML comment (<!--...-->) causes Smarty 3.1.21 to generate malformed PHP.
# The pattern: label="<!--{t|escape:'javascript'}--><!--{/t}-->"
# generates eval()'d PHP code that fails with:
#   "unexpected '$_block_content'" on line 641
# Fix: remove the bare HTML comment opener and replace the empty {t} block
# with an empty string in the label attribute.
# -----------------------------------------------------------------------
echo "Fixing encounterconsole.tpl Smarty PHP parse error..."
python3 -c "
tpl_path = '${FREEMED_DIR}/ui/dojo/view/org.freemedsoftware.ui.encounterconsole.tpl'
with open(tpl_path, 'r') as f:
    content = f.read()
# Fix: remove the empty t block in the label attribute
old = \"label=\\\"<!--{t|escape:'javascript'}--><!--{/t}-->\\\"\"
new = \"label=\\\"\\\"\"
if old in content:
    content = content.replace(old, new)
    with open(tpl_path, 'w') as f:
        f.write(content)
    print('encounterconsole.tpl fixed: removed empty t block from label attribute')
else:
    print('encounterconsole.tpl already fixed or pattern not found')
" 2>/dev/null || echo "encounterconsole.tpl fix skipped"


# -----------------------------------------------------------------------
# Create settings.php (FreeMED configuration)
# Using Dojo UI (UI=dojo) - GWT UI requires Java compilation
# -----------------------------------------------------------------------
echo "Creating FreeMED settings.php..."
cat > "${FREEMED_DIR}/lib/settings.php" << 'SETTINGSEOF'
<?php
define ("INSTALLATION", "FreeMED Demo");
define ("DB_HOST", "localhost");
define ("DB_NAME", "freemed");
define ("DB_USER", "freemed");
define ("DB_PASSWORD", "freemed");
define ("PATID_PREFIX", "FMD");
define ("UI", "dojo");
define ("HOST", "localhost");
define ("BASE_URL", "/freemed");
define ("SESSION_PROTECTION", true);
define ("RECORD_LOCK_TIMEOUT", 180);
define ("DEFAULT_LANGUAGE", "en_US");
define ("INIT_ADDR", "127.0.0.1");
define ("FSF_USERNAME", "");
define ("FSF_PASSWORD", "");
?>
SETTINGSEOF

# -----------------------------------------------------------------------
# Initialize FreeMED database from schema files
# Must run from FreeMED directory due to SOURCE commands in SQL files
# -----------------------------------------------------------------------
echo "Initializing FreeMED database schema..."
cd "$FREEMED_DIR"

# Load schema files - strip SOURCE commands to avoid recursive loading issues
# (SQL files have SOURCE lines that cause recursive loading of dependencies)
# Run with root MySQL to allow stored procedure creation
for f in data/schema/mysql/*.sql; do
    [ -f "$f" ] || continue
    [ -d "$f" ] && continue
    # Strip SOURCE lines (we load each file exactly once)
    grep -v '^SOURCE' "$f" | mysql "${FREEMED_DB}" 2>/dev/null || true
done

# Check if patient table was created
if ! mysql "${FREEMED_DB}" -e "DESCRIBE patient;" 2>/dev/null | grep -q ptfname; then
    echo "Warning: patient table may not have loaded"
fi

echo "Database schema loaded"

# -----------------------------------------------------------------------
# Create admin user
# -----------------------------------------------------------------------
echo "Creating admin user..."
mysql "${FREEMED_DB}" -e "INSERT IGNORE INTO user
    (username, userpassword, userdescrip, usertype, userfname, userlname)
    VALUES ('${FREEMED_ADMIN_USER}', MD5('${FREEMED_ADMIN_PASS}'),
            'System Administrator', 'super', 'Admin', 'User');" 2>/dev/null

ADMIN_COUNT=$(mysql "${FREEMED_DB}" -N -e "SELECT COUNT(*) FROM user WHERE username='${FREEMED_ADMIN_USER}';" 2>/dev/null || echo "0")
echo "Admin user count: $ADMIN_COUNT"

# -----------------------------------------------------------------------
# Mark FreeMED as installed
# -----------------------------------------------------------------------
mkdir -p "${FREEMED_DIR}/data/cache"
touch "${FREEMED_DIR}/data/cache/healthy"
mkdir -p "${FREEMED_DIR}/data/log"
echo "Installed marker created"

# -----------------------------------------------------------------------
# Set permissions
# -----------------------------------------------------------------------
chown -R www-data:www-data "${FREEMED_DIR}/"
chmod -R 755 "${FREEMED_DIR}/"
chmod -R 777 "${FREEMED_DIR}/data/cache"
chmod -R 777 "${FREEMED_DIR}/data/log"

# -----------------------------------------------------------------------
# Configure Apache to serve FreeMED at /freemed
# -----------------------------------------------------------------------
echo "Configuring Apache..."
cat > /etc/apache2/sites-available/freemed.conf << 'APACHEEOF'
Alias /freemed /usr/share/freemed

<Directory /usr/share/freemed>
    Options FollowSymLinks
    AllowOverride All
    Require all granted
    DirectoryIndex index.php index.html
    php_value memory_limit 128M
    php_value upload_max_filesize 64M
    php_value post_max_size 64M
</Directory>
APACHEEOF

a2ensite freemed 2>/dev/null || true
systemctl reload apache2 || service apache2 reload
sleep 2

# -----------------------------------------------------------------------
# Verify FreeMED web UI is accessible
# -----------------------------------------------------------------------
echo "Verifying FreeMED web UI..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${FREEMED_URL}" 2>/dev/null)
if [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "200" ]; then
    echo "FreeMED web UI is accessible (HTTP $HTTP_CODE)"
else
    echo "WARNING: FreeMED returned HTTP $HTTP_CODE (expected 200 or 302)"
    tail -10 /var/log/apache2/error.log 2>/dev/null || true
fi

# -----------------------------------------------------------------------
# Load realistic patient data
# -----------------------------------------------------------------------
echo ""
echo "Loading patient data..."
PATIENT_COUNT=$(mysql -u "${FREEMED_DB_USER}" -p"${FREEMED_DB_PASS}" "${FREEMED_DB}" -N \
    -e "SELECT COUNT(*) FROM patient" 2>/dev/null || echo "0")
echo "Current patient count: $PATIENT_COUNT"

if [ "$PATIENT_COUNT" = "0" ] || [ -z "$PATIENT_COUNT" ]; then
    echo "Inserting patient data..."
    mysql "${FREEMED_DB}" < /workspace/data/patients.sql 2>/dev/null
    PATIENT_COUNT_AFTER=$(mysql "${FREEMED_DB}" -N \
        -e "SELECT COUNT(*) FROM patient" 2>/dev/null || echo "0")
    echo "Patients loaded: $PATIENT_COUNT_AFTER"
else
    echo "Patient data already present ($PATIENT_COUNT patients)"
fi

# -----------------------------------------------------------------------
# Create utility script for DB queries
# -----------------------------------------------------------------------
cat > /usr/local/bin/freemed-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against FreeMED database (direct LAMP)
mysql -u freemed -pfreemed freemed -N -e "$1" 2>/dev/null
DBQUERYEOF
chmod +x /usr/local/bin/freemed-db-query

# -----------------------------------------------------------------------
# Set up Firefox profile
# -----------------------------------------------------------------------
echo ""
echo "Setting up Firefox profile..."

# Detect snap Firefox vs. regular Firefox
if [ -x /snap/bin/firefox ]; then
    PROFILE_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
    FF_CMD="/snap/bin/firefox"
else
    PROFILE_BASE="/home/ga/.mozilla/firefox"
    FF_CMD="firefox"
fi

mkdir -p "${PROFILE_BASE}/freemed.profile"
# Fix ownership from root to ga (snap directory created as root)
chown -R ga:ga /home/ga/snap/ 2>/dev/null || true
chown -R ga:ga "${PROFILE_BASE}/" 2>/dev/null || true

# Create profiles.ini
cat > "${PROFILE_BASE}/profiles.ini" << 'FFPROFILEEOF'
[Install4F96D1932A9F858E]
Default=freemed.profile
Locked=1

[Profile0]
Name=freemed
IsRelative=1
Path=freemed.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILEEOF

# Create user.js to suppress first-run dialogs and set homepage
cat > "${PROFILE_BASE}/freemed.profile/user.js" << USERJS
// Disable first-run screens
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to FreeMED login
user_pref("browser.startup.homepage", "${FREEMED_URL}");
user_pref("browser.startup.page", 1);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable sidebar and popups
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
USERJS

chown -R ga:ga "${PROFILE_BASE}/"

# -----------------------------------------------------------------------
# Create desktop shortcut
# -----------------------------------------------------------------------
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/FreeMED.desktop << DESKTOPEOF
[Desktop Entry]
Name=FreeMED
Comment=Electronic Medical Record System
Exec=${FF_CMD} http://localhost/freemed/
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Medical;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/FreeMED.desktop
chmod +x /home/ga/Desktop/FreeMED.desktop

# -----------------------------------------------------------------------
# Launch Firefox pointing to FreeMED login page
# -----------------------------------------------------------------------
echo ""
echo "Launching Firefox with FreeMED..."

# Kill any existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Remove stale lock files
rm -f "${PROFILE_BASE}/freemed.profile/.parentlock" \
      "${PROFILE_BASE}/freemed.profile/lock" 2>/dev/null || true

# Launch Firefox (setsid to detach from SSH session)
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid ${FF_CMD} --new-instance \
    -profile '${PROFILE_BASE}/freemed.profile' \
    '${FREEMED_URL}' > /tmp/firefox_freemed.log 2>&1 &"

# Wait for Firefox window
for i in $(seq 1 30); do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|freemed"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done
sleep 3

# Maximize Firefox window
WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | \
      grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: \
        -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox window maximized"
fi

echo ""
echo "=== FreeMED Setup Complete ==="
echo ""
echo "FreeMED is running at: http://localhost/freemed/"
echo ""
echo "Login Credentials:"
echo "  Username: admin"
echo "  Password: admin"
echo ""
echo "Patient count: $(mysql freemed -N -e 'SELECT COUNT(*) FROM patient;' 2>/dev/null)"
echo ""
echo "Database access:"
echo "  mysql freemed -e 'SELECT id, ptfname, ptlname FROM patient;'"
echo "  freemed-db-query 'SELECT COUNT(*) FROM patient'"
