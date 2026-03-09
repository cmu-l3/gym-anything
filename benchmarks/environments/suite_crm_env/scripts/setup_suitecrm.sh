#!/bin/bash
set -e

echo "=== Setting up SuiteCRM ==="

# Wait for desktop to be ready
sleep 5

# ---------------------------------------------------------------
# 1. Prepare SuiteCRM directory and configuration
# ---------------------------------------------------------------
echo "--- Preparing SuiteCRM configuration ---"
mkdir -p /home/ga/suitecrm/docker
cp /workspace/config/docker-compose.yml /home/ga/suitecrm/
cp /workspace/config/Dockerfile /home/ga/suitecrm/docker/
cp /workspace/config/entrypoint.sh /home/ga/suitecrm/docker/
chown -R ga:ga /home/ga/suitecrm

# ---------------------------------------------------------------
# 2. Start Docker containers
# ---------------------------------------------------------------
echo "--- Starting Docker containers ---"
cd /home/ga/suitecrm
docker compose build --no-cache
docker compose up -d

# Wait for MariaDB to be ready
echo "--- Waiting for MariaDB ---"
wait_for_mysql() {
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker exec suitecrm-db mysqladmin ping -h localhost -u root -proot_pass 2>/dev/null | grep -q "alive"; then
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
# 3. Wait for SuiteCRM web server to respond
# ---------------------------------------------------------------
echo "--- Waiting for SuiteCRM application ---"
wait_for_suitecrm() {
    local timeout=180
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/install.php 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "SuiteCRM is ready (HTTP $HTTP_CODE) (${elapsed}s)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... (${elapsed}s, HTTP $HTTP_CODE)"
    done
    echo "SuiteCRM timeout after ${timeout}s"
    return 1
}
wait_for_suitecrm

# ---------------------------------------------------------------
# 4. Run SuiteCRM silent install
# ---------------------------------------------------------------
echo "--- Running SuiteCRM silent install ---"

# Copy silent install config into the container
docker cp /workspace/config/config_si.php suitecrm-app:/var/www/html/config_si.php
docker exec suitecrm-app chown www-data:www-data /var/www/html/config_si.php

# SuiteCRM 7.x silent install via PHP CLI
# This is the documented approach: set $_SERVER vars and include install.php
echo "  Running PHP CLI silent install..."
docker exec -u www-data suitecrm-app bash -c 'cd /var/www/html && php -r "\$_SERVER[\"HTTP_HOST\"] = \"localhost\"; \$_SERVER[\"REQUEST_URI\"] = \"install.php\"; \$_REQUEST = array(\"goto\" => \"SilentInstall\", \"cli\" => true); require_once \"install.php\";"' 2>&1 | tail -20 || true
sleep 10

# Verify config.php was created
CONFIG_EXISTS=$(docker exec suitecrm-app test -f /var/www/html/config.php && echo "yes" || echo "no")
echo "  config.php exists: $CONFIG_EXISTS"

if [ "$CONFIG_EXISTS" = "no" ]; then
    echo "  PHP CLI install failed, trying curl-based approach..."
    # Fallback: use curl with cookies to simulate browser install
    curl -c /tmp/suitecrm_cookies.txt -b /tmp/suitecrm_cookies.txt \
        -s "http://localhost:8000/install.php?goto=SilentInstall&cli=true" > /dev/null 2>&1 || true
    sleep 30
    CONFIG_EXISTS=$(docker exec suitecrm-app test -f /var/www/html/config.php && echo "yes" || echo "no")
    echo "  config.php exists after curl: $CONFIG_EXISTS"
fi

echo "  Silent install done"

# Fix permissions after install
docker exec suitecrm-app bash -c "
    chmod -R 775 /var/www/html/cache
    chmod -R 775 /var/www/html/custom
    chmod -R 775 /var/www/html/modules
    chmod -R 775 /var/www/html/upload
    chmod 775 /var/www/html/config.php 2>/dev/null
    chmod 775 /var/www/html/config_override.php 2>/dev/null
    chmod 775 /var/www/html/.htaccess 2>/dev/null
    chown -R www-data:www-data /var/www/html
" 2>/dev/null || true

# Restart Apache to pick up new config
docker exec suitecrm-app apache2ctl restart 2>/dev/null || true
sleep 5

# Verify install succeeded by checking for config.php
CONFIG_CHECK=$(docker exec suitecrm-app test -f /var/www/html/config.php && echo "ok" || echo "fail")
if [ "$CONFIG_CHECK" = "ok" ]; then
    echo "  SuiteCRM config.php exists"
else
    echo "  WARNING: config.php not found, install may have failed"
fi

# Verify login page loads (follow redirects)
LOGIN_CHECK=$(curl -sL http://localhost:8000/ 2>/dev/null | grep -ci "log.in\|LBL_LOGIN" || true)
if [ -n "$LOGIN_CHECK" ] && [ "$LOGIN_CHECK" -gt 0 ] 2>/dev/null; then
    echo "  Login page verified OK"
else
    echo "  WARNING: Login page check returned $LOGIN_CHECK"
fi

# ---------------------------------------------------------------
# 5. Seed realistic CRM data
# ---------------------------------------------------------------
echo "--- Seeding CRM data ---"
cp /workspace/utils/seed_data.php /tmp/seed_data.php
docker cp /tmp/seed_data.php suitecrm-app:/tmp/seed_data.php
docker exec suitecrm-app php /tmp/seed_data.php 2>&1 | tail -10 || true
echo "  Data seeding complete"

# ---------------------------------------------------------------
# 6. Verify data was loaded
# ---------------------------------------------------------------
echo "--- Verifying seeded data ---"
ACCOUNT_COUNT=$(docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "SELECT COUNT(*) FROM accounts WHERE deleted=0" 2>/dev/null || echo "0")
CONTACT_COUNT=$(docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "SELECT COUNT(*) FROM contacts WHERE deleted=0" 2>/dev/null || echo "0")
OPP_COUNT=$(docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "SELECT COUNT(*) FROM opportunities WHERE deleted=0" 2>/dev/null || echo "0")
CASE_COUNT=$(docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "SELECT COUNT(*) FROM cases WHERE deleted=0" 2>/dev/null || echo "0")
echo "  Accounts: $ACCOUNT_COUNT"
echo "  Contacts: $CONTACT_COUNT"
echo "  Opportunities: $OPP_COUNT"
echo "  Cases: $CASE_COUNT"

# ---------------------------------------------------------------
# 7. Create database query helper
# ---------------------------------------------------------------
echo "--- Creating database query helper ---"
cat > /usr/local/bin/suitecrm-db-query << 'DBEOF'
#!/bin/bash
# Execute SQL query against SuiteCRM database
docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "$1" 2>/dev/null
DBEOF
chmod +x /usr/local/bin/suitecrm-db-query

# ---------------------------------------------------------------
# 8. Setup Firefox
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
cat > /home/ga/Desktop/SuiteCRM.desktop << 'DSKEOF'
[Desktop Entry]
Name=SuiteCRM
Comment=Customer Relationship Management
Exec=firefox http://localhost:8000
Icon=firefox
Terminal=false
Type=Application
Categories=Network;WebBrowser;
DSKEOF
chmod +x /home/ga/Desktop/SuiteCRM.desktop
chown ga:ga /home/ga/Desktop/SuiteCRM.desktop

# ---------------------------------------------------------------
# 9. Launch Firefox and perform initial login
# ---------------------------------------------------------------
echo "--- Launching Firefox ---"
su - ga -c "DISPLAY=:1 firefox http://localhost:8000/ &"

# Wait for Firefox window to appear
echo "--- Waiting for Firefox window ---"
FIREFOX_TIMEOUT=60
FIREFOX_ELAPSED=0
while [ $FIREFOX_ELAPSED -lt $FIREFOX_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iq "firefox\|suitecrm\|mozilla"; then
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
# 10. Auto-login to SuiteCRM (coordinates at 1920x1080)
# ---------------------------------------------------------------
echo "--- Logging into SuiteCRM ---"

# Wait for Firefox to fully render the login page
sleep 12

# SuiteCRM 7.x login page - coordinates calibrated via visual_grounding
# At 1920x1080: Username=(995,480), Password=(995,539), LOG IN=(995,597)
# Note: If "session expired" banner present, fields shift ~30px down
DISPLAY=:1 xdotool mousemove 995 480
sleep 0.3
DISPLAY=:1 xdotool click 1
sleep 0.5
DISPLAY=:1 xdotool click --repeat 3 1
sleep 0.2
DISPLAY=:1 xdotool type --delay 30 "admin"
sleep 0.3

# Tab to password field
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type --delay 30 "Admin1234!"
sleep 0.3

# Click LOG IN button
DISPLAY=:1 xdotool mousemove 995 597
sleep 0.3
DISPLAY=:1 xdotool click 1
sleep 8

# SuiteCRM may show a first-login setup wizard or redirect to dashboard
# Navigate to home/dashboard to ensure we're on the main page
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.2
DISPLAY=:1 xdotool type --delay 20 "http://localhost:8000/index.php?module=Home&action=index"
DISPLAY=:1 xdotool key Return
sleep 5

echo "=== SuiteCRM setup complete ==="
echo "  URL: http://localhost:8000"
echo "  Admin: admin / Admin1234!"
