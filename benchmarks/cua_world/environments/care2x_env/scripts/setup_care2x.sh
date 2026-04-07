#!/bin/bash
# Care2x HIS Setup Script (post_start hook)
# Starts services, creates database, runs installer programmatically,
# seeds realistic patient data, and launches Firefox.
#
# Care2x credentials: admin / care2x_admin
# URL: http://localhost/

set -e

echo "=== Setting up Care2x Hospital Information System ==="

CARE2X_URL="http://localhost"
CARE2X_DB="care2x"
CARE2X_DB_USER="care2x"
CARE2X_DB_PASS="care2x_pass"

# ── Helper: wait for service ─────────────────────────────────────────────────
wait_for_service() {
    local check_cmd="$1"
    local timeout="${2:-60}"
    local elapsed=0
    echo "Waiting for service (timeout ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if eval "$check_cmd" > /dev/null 2>&1; then
            echo "  Service ready after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Timeout waiting for service after ${timeout}s"
    return 1
}

wait_for_http() {
    local url="$1"
    local timeout="${2:-120}"
    local elapsed=0
    echo "Polling $url (timeout ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "  Ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done
    echo "WARNING: Timeout waiting for $url after ${timeout}s"
    return 1
}

# ── 1. Start services ────────────────────────────────────────────────────────
echo "Starting MariaDB..."
systemctl start mariadb
wait_for_service "mysqladmin ping --silent" 60

echo "Starting Apache..."
systemctl start apache2
wait_for_service "curl -s http://localhost/ > /dev/null 2>&1" 30

# ── 2. Create database and user ──────────────────────────────────────────────
echo "Creating Care2x database and user..."
mysql -u root << EOSQL
CREATE DATABASE IF NOT EXISTS ${CARE2X_DB} CHARACTER SET latin1 COLLATE latin1_general_ci;
CREATE USER IF NOT EXISTS '${CARE2X_DB_USER}'@'localhost' IDENTIFIED BY '${CARE2X_DB_PASS}';
GRANT ALL PRIVILEGES ON ${CARE2X_DB}.* TO '${CARE2X_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOSQL

echo "Database '${CARE2X_DB}' created successfully."

# ── 3. Configure Care2x database connection ──────────────────────────────────
echo "Configuring Care2x database connection..."

# Care2x reads DB config from include/core/inc_init_main.php
INIT_MAIN="/var/www/html/care2x/include/core/inc_init_main.php"
if [ -f "$INIT_MAIN" ]; then
    sed -i "s|\\\$dbname=.*|\\\$dbname='${CARE2X_DB}';|" "$INIT_MAIN"
    sed -i "s|\\\$dbusername=.*|\\\$dbusername='${CARE2X_DB_USER}';|" "$INIT_MAIN"
    sed -i "s|\\\$dbpassword=.*|\\\$dbpassword='${CARE2X_DB_PASS}';|" "$INIT_MAIN"
    sed -i "s|\\\$dbhost=.*|\\\$dbhost='localhost';|" "$INIT_MAIN"
    sed -i "s|\\\$dbtype=.*|\\\$dbtype='mysqli';|" "$INIT_MAIN"
    sed -i "s|\\\$main_domain=.*|\\\$main_domain='localhost/';|" "$INIT_MAIN"
    sed -i "s|\\\$photoserver_ip=.*|\\\$photoserver_ip='localhost/';|" "$INIT_MAIN"
    sed -i "s|\\\$httprotocol=.*|\\\$httprotocol='http';|" "$INIT_MAIN"
    echo "Database connection configured in $INIT_MAIN"
fi

# Also update the helpers copy of the same config
INIT_HELPERS="/var/www/html/care2x/include/helpers/inc_init_main.php"
if [ -f "$INIT_HELPERS" ]; then
    sed -i "s|\\\$dbname=.*|\\\$dbname='${CARE2X_DB}';|" "$INIT_HELPERS"
    sed -i "s|\\\$dbusername=.*|\\\$dbusername='${CARE2X_DB_USER}';|" "$INIT_HELPERS"
    sed -i "s|\\\$dbpassword=.*|\\\$dbpassword='${CARE2X_DB_PASS}';|" "$INIT_HELPERS"
    sed -i "s|\\\$dbhost=.*|\\\$dbhost='localhost';|" "$INIT_HELPERS"
    echo "Database connection configured in $INIT_HELPERS"
fi

# Also write a separate db_config.php for any code that loads it
GLOBAL_CONF="/var/www/html/care2x/global_conf"

# ── 4. Import database schema ────────────────────────────────────────────────
echo "Importing Care2x database schema..."

# Import the SQL dump - strip COLLATE/CHARSET directives that cause failures
SQL_DUMP="/var/www/html/care2x/installer/db/sql/mysqli_dump.sql"
if [ -f "$SQL_DUMP" ]; then
    echo "Importing Care2x schema from $SQL_DUMP..."
    # First pass: import as-is (works for most tables)
    mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" < "$SQL_DUMP" 2>/dev/null || true
    # Second pass: strip collation/charset for tables that failed, but do NOT drop existing tables
    sed -e 's/ COLLATE [a-zA-Z0-9_]*//gi' \
        -e 's/ COLLATE=[a-zA-Z0-9_]*//gi' \
        -e 's/ DEFAULT CHARSET=[a-zA-Z0-9_]*//gi' \
        -e '/^DROP TABLE/d' \
        "$SQL_DUMP" | mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" 2>/dev/null || true
    echo "Schema import done."
fi

# Import additional data files
for sql_file in /var/www/html/care2x/installer/db/sql/care_*.sql; do
    if [ -f "$sql_file" ]; then
        echo "Importing $(basename $sql_file)..."
        mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" < "$sql_file" 2>/dev/null || {
            echo "Warning: Errors importing $(basename $sql_file) (non-fatal)"
        }
    fi
done

# Verify key tables exist
echo "Verifying key tables..."
TABLE_COUNT=$(mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${CARE2X_DB}';" 2>/dev/null || echo "0")
echo "Total tables created: $TABLE_COUNT"

# Ensure care_users table exists (may fail to create from dump due to charset issues)
mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -e "
CREATE TABLE IF NOT EXISTS care_users (
  name varchar(60) NOT NULL DEFAULT '',
  login_id varchar(35) NOT NULL,
  password varchar(255) DEFAULT NULL,
  staff_nr int(10) unsigned NOT NULL DEFAULT 0,
  lockflag tinyint(3) unsigned DEFAULT 0,
  permission text NOT NULL,
  exc tinyint(1) NOT NULL DEFAULT 0,
  s_date date NOT NULL DEFAULT '0000-00-00',
  s_time time NOT NULL DEFAULT '00:00:00',
  expire_date date NOT NULL DEFAULT '0000-00-00',
  expire_time time NOT NULL DEFAULT '00:00:00',
  dept_nr text NOT NULL,
  user_role tinyint(4) NOT NULL DEFAULT 0,
  status varchar(15) NOT NULL DEFAULT '',
  history text NOT NULL,
  modify_id varchar(35) NOT NULL DEFAULT '',
  modify_time timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  create_id varchar(35) NOT NULL DEFAULT '',
  create_time timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (login_id)
);
" 2>/dev/null || true
echo "care_users table ensured."

# ── 5. Create admin user ────────────────────────────────────────────────────
echo "Setting up admin user..."
ADMIN_PASS_HASH=$(echo -n "care2x_admin" | md5sum | awk '{print $1}')

mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -e "
    INSERT INTO care_users (name, login_id, password, permission, exc, dept_nr, history, modify_id, create_id, status)
    VALUES ('Administrator', 'admin', '${ADMIN_PASS_HASH}', 'System_Admin', 1, '', '', 'auto-setup', 'auto-setup', 'normal')
    ON DUPLICATE KEY UPDATE password='${ADMIN_PASS_HASH}';
" 2>/dev/null || echo "Warning: Could not create admin user"

ADMIN_CHECK=$(mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -N -e "SELECT login_id FROM care_users WHERE login_id='admin';" 2>/dev/null || echo "")
echo "Admin user: $ADMIN_CHECK"

# ── 5b. Seed global config (required for Care2x to function) ────────────────
echo "Seeding global configuration..."
mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -e "
INSERT IGNORE INTO care_config_global (type, value, status, history, modify_id, create_id) VALUES
('language_single', '1', 'normal', '', 'admin', 'admin'),
('language_default', 'en', 'normal', '', 'admin', 'admin'),
('language_non_single', 'en', 'normal', '', 'admin', 'admin'),
('gui_frame_left_nav_width', '180', 'normal', '', 'admin', 'admin'),
('gui_frame_left_nav_border', '0', 'normal', '', 'admin', 'admin'),
('timeout_inactive', '1', 'normal', '', 'admin', 'admin'),
('timeout_time', '3000', 'normal', '', 'admin', 'admin');
" 2>/dev/null || true
echo "Global config seeded."

# Seed default user config (required to avoid infinite loop in _getDefault)
mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -e "
ALTER TABLE care_config_user
    MODIFY status varchar(25) NOT NULL DEFAULT 'normal',
    MODIFY history mediumtext DEFAULT NULL,
    MODIFY modify_id varchar(35) NOT NULL DEFAULT 'system',
    MODIFY create_id varchar(35) NOT NULL DEFAULT 'system';
INSERT IGNORE INTO care_config_user (user_id, serial_config_data, status, modify_id, create_id) VALUES
('default', 'a:10:{s:4:\"lang\";s:2:\"en\";s:5:\"bname\";s:7:\"mozilla\";s:8:\"bversion\";s:3:\"5.0\";s:3:\"cid\";s:0:\"\";s:4:\"mask\";s:1:\"1\";s:5:\"dhtml\";i:1;s:2:\"ip\";s:9:\"127.0.0.1\";s:14:\"template_theme\";s:7:\"default\";s:14:\"template_smarty\";s:7:\"default\";s:12:\"config_theme\";s:0:\"\";}', 'normal', 'admin', 'admin');
" 2>/dev/null || true
echo "Default user config seeded."

# ── 5c. Fix PHP/Care2x compatibility issues ──────────────────────────────────
echo "Applying Care2x compatibility fixes..."

# Fix hcemd5.php to handle empty cookie data gracefully
HCEMD5="/var/www/html/care2x/classes/pear/crypt/hcemd5.php"
if [ -f "$HCEMD5" ]; then
    sed -i 's/list($rand, $data_crypt) = explode/#, $data);/if(empty($data)){return false;}list($rand, $data_crypt) = explode('"'"'#'"'"', $data);\/\//' "$HCEMD5" 2>/dev/null || true
    # Simpler approach: add empty check before explode
    sed -i '/function decodeMimeSelfRand/,/list.*explode/{s/list(\$rand, \$data_crypt) = explode.*$/if(empty($data)||strpos($data,"#")===false){return false;}list($rand, $data_crypt) = explode("#", $data);/}' "$HCEMD5" 2>/dev/null || true
fi

# Disable Smarty debug mode
SMARTY_CARE="/var/www/html/care2x/gui/smarty_template/smarty_care.class.php"
if [ -f "$SMARTY_CARE" ]; then
    sed -i 's/\$this->debug = true;/\$this->debug = false;/' "$SMARTY_CARE"
fi

# Fix AdodbPdoShim.php syntax error (duplicate else block)
ADODB_SHIM="/var/www/html/care2x/include/core/AdodbPdoShim.php"
if [ -f "$ADODB_SHIM" ]; then
    # Check for the duplicate } else { throw $e; } block and remove it
    php -l "$ADODB_SHIM" 2>&1 | grep -q "syntax error" && {
        # Find and remove duplicate else block (lines after the first } else { throw $e; } })
        python3 -c "
import re
with open('$ADODB_SHIM') as f:
    content = f.read()
# Remove the duplicate '} else {\n                throw \$e;\n            }' block
content = content.replace('            } else {\n                throw \$e;\n            }\n            } else {\n                throw \$e;\n            }', '            } else {\n                throw \$e;\n            }')
with open('$ADODB_SHIM','w') as f:
    f.write(content)
" 2>/dev/null || true
        echo "AdodbPdoShim syntax fixed."
    }
fi

# Deploy custom navigation page (workaround for Smarty/PHP8 500 errors in indexframe)
if [ -f "/workspace/config/nav.php" ]; then
    cp /workspace/config/nav.php /var/www/html/care2x/main/nav.php
    chown www-data:www-data /var/www/html/care2x/main/nav.php
    # Update frameset to use nav.php instead of indexframe.php
    sed -i 's|main/indexframe.php|main/nav.php|g' /var/www/html/care2x/index.php
    echo "Custom navigation deployed."
fi

# Create .htaccess for PHP settings
cat > /var/www/html/care2x/.htaccess << 'HTEOF'
php_value memory_limit 2048M
php_value max_execution_time 300
php_value display_errors 0
php_value error_reporting 0
HTEOF
chown www-data:www-data /var/www/html/care2x/.htaccess

# Set PHP memory limit in php.ini
PHP_INI_DIR=$(find /etc/php -type d -name 'apache2' 2>/dev/null | head -1)
if [ -n "$PHP_INI_DIR" ]; then
    echo "memory_limit=2048M" > "$PHP_INI_DIR/conf.d/99-care2x.ini"
    echo "max_execution_time=300" >> "$PHP_INI_DIR/conf.d/99-care2x.ini"
    echo "display_errors=Off" >> "$PHP_INI_DIR/conf.d/99-care2x.ini"
    echo "error_reporting=0" >> "$PHP_INI_DIR/conf.d/99-care2x.ini"
fi

# ── 6. Configure Care2x database connection and mark installed ────────────────
echo "Configuring Care2x database connection..."

# Write the database configuration that Care2x reads
cat > "$GLOBAL_CONF/db_config.php" << PHPEOF
<?php
\$db_type = 'mysqli';
\$db_host = 'localhost';
\$db_name = '${CARE2X_DB}';
\$db_user = '${CARE2X_DB_USER}';
\$db_password = '${CARE2X_DB_PASS}';
?>
PHPEOF

chown www-data:www-data "$GLOBAL_CONF/db_config.php"

# Mark as installed: Care2x checks for installer/install.php existence
# and redirects to installer if found. Remove it to bypass.
if [ -f "/var/www/html/care2x/installer/install.php" ]; then
    mv /var/www/html/care2x/installer/install.php /var/www/html/care2x/installer/install.php.disabled
    echo "Installer disabled (install.php renamed)"
fi

# ── 7. Seed realistic patient data ───────────────────────────────────────────
echo "Seeding realistic patient data..."
bash /workspace/scripts/seed_data.sh || echo "WARNING: Data seeding had errors (non-fatal)"

# ── 8. Ensure proper permissions ─────────────────────────────────────────────
chown -R www-data:www-data /var/www/html/care2x
chmod -R 755 /var/www/html/care2x
chmod -R 777 /var/www/html/care2x/cache
chmod -R 777 /var/www/html/care2x/uploads

# Restart Apache to pick up all changes
systemctl restart apache2
sleep 3

# ── 9. Firefox profile setup ─────────────────────────────────────────────────
echo "Configuring Firefox profile..."
FIREFOX_DIR="/home/ga/.mozilla/firefox"
PROFILE_DIR="$FIREFOX_DIR/care2x.default"
sudo -u ga mkdir -p "$PROFILE_DIR"

cat > "$FIREFOX_DIR/profiles.ini" << 'FFINI'
[Install4F96D1932A9F858E]
Default=care2x.default
Locked=1

[Profile0]
Name=care2x
IsRelative=1
Path=care2x.default
Default=1

[General]
StartWithLastProfile=1
Version=2
FFINI

cat > "$PROFILE_DIR/user.js" << USERJS
// Disable first-run dialogs
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
// Homepage = Care2x
user_pref("browser.startup.homepage", "${CARE2X_URL}");
user_pref("browser.startup.page", 1);
// Disable updates
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
// Disable password saving
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
// Disable sidebar/promo
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
// Disable session restore prompts
user_pref("browser.sessionstore.resume_from_crash", false);
USERJS

chown -R ga:ga "$FIREFOX_DIR"

# ── 10. Launch Firefox ────────────────────────────────────────────────────────
echo "Launching Firefox with Care2x..."
su - ga -c "DISPLAY=:1 firefox '${CARE2X_URL}' > /tmp/firefox_care2x.log 2>&1 &"

# Wait for Firefox window
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|care2x"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

sleep 2

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# ── 11. Verify Care2x is accessible ──────────────────────────────────────────
echo "Verifying Care2x accessibility..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "${CARE2X_URL}/index.php" 2>/dev/null || echo "000")
echo "Main page HTTP status: $HTTP_CODE"

PATIENT_COUNT=$(mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -N -e "SELECT COUNT(*) FROM care_person;" 2>/dev/null || echo "0")
echo "Patients in database: $PATIENT_COUNT"

TABLE_COUNT=$(mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${CARE2X_DB}';" 2>/dev/null || echo "0")
echo "Tables in database: $TABLE_COUNT"

echo ""
echo "=== Care2x Setup Complete ==="
echo ""
echo "URL:      ${CARE2X_URL}"
echo "Login:    admin / care2x_admin"
echo "DB:       ${CARE2X_DB} (user: ${CARE2X_DB_USER})"
echo ""
