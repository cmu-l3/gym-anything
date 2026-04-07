#!/bin/bash
# ManageEngine OpManager Setup Script (post_start hook)
# Starts OpManager service, waits for web UI, changes default password,
# and launches Firefox on the dashboard.
#
# Default credentials: admin / admin  →  Changed to: admin / Admin@123
# Web UI: http://localhost:8060

echo "=== Setting up ManageEngine OpManager ==="

# Read install dir from pre_start
OPMANAGER_DIR=$(cat /tmp/opmanager_install_dir 2>/dev/null || echo "/opt/ManageEngine/OpManager")
OPMANAGER_URL="http://localhost:8060"
ADMIN_USER="admin"
DEFAULT_PASS="admin"
ADMIN_PASS="Admin@123"

# ============================================================
# 1. Ensure SNMP agent is running (provides real monitoring data)
# ============================================================
echo "Ensuring SNMP agent is running..."
systemctl restart snmpd 2>/dev/null || true
sleep 2

# Verify SNMP is responding with real system data
echo "SNMP system data (real):"
snmpwalk -v2c -c public 127.0.0.1 sysDescr 2>/dev/null || echo "SNMP check deferred"
snmpwalk -v2c -c public 127.0.0.1 hrProcessorLoad 2>/dev/null | head -3 || true

# ============================================================
# 2. Start ManageEngine OpManager
# ============================================================
echo "Starting ManageEngine OpManager..."

# Try systemd first (service file has correct WorkingDirectory=bin/)
if systemctl start OpManager.service 2>/dev/null; then
    echo "OpManager started via systemd"
else
    echo "Systemd start failed, starting directly from bin/ directory..."
    cd "$OPMANAGER_DIR/bin"
    nohup ./run.sh > /tmp/opmanager_startup.log 2>&1 &
    echo "OpManager started directly (PID: $!)"
fi

# ============================================================
# 3. Wait for OpManager web UI (increased timeout: 480s)
# ============================================================
wait_for_opmanager() {
    local timeout=${1:-480}
    local elapsed=0

    echo "Waiting for OpManager web UI to be ready (timeout: ${timeout}s)..."

    while [ $elapsed -lt $timeout ]; do
        # Check if the web server is responding
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$OPMANAGER_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "OpManager web UI is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi

        # Also check the login page directly
        HTTP_CODE2=$(curl -s -o /dev/null -w "%{http_code}" "${OPMANAGER_URL}/apiclient/ember/Login.jsp" 2>/dev/null)
        if [ "$HTTP_CODE2" = "200" ]; then
            echo "OpManager login page is ready after ${elapsed}s"
            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))

        # Show progress every 60 seconds
        if [ $((elapsed % 60)) -eq 0 ]; then
            echo "  Still waiting... ${elapsed}s (HTTP: $HTTP_CODE / $HTTP_CODE2)"
            # Check if Java process is running
            if pgrep -f "$OPMANAGER_DIR/jre/bin/java" > /dev/null 2>&1; then
                echo "  OpManager Java process is running"
            else
                echo "  WARNING: OpManager Java process not detected, attempting restart..."
                cd "$OPMANAGER_DIR/bin"
                nohup ./run.sh > /tmp/opmanager_startup.log 2>&1 &
            fi
        fi
    done

    echo "WARNING: OpManager readiness check timed out after ${timeout}s"
    return 1
}

wait_for_opmanager 480

# ============================================================
# 4. Wait for PostgreSQL and full initialization (increased: 180s)
# ============================================================
PGSQL_DIR="$OPMANAGER_DIR/pgsql"
PG_BIN="$PGSQL_DIR/bin/psql"
PG_PORT=""

# Find PostgreSQL port from config
if [ -f "$OPMANAGER_DIR/conf/database_params.conf" ]; then
    PG_PORT=$(grep "url=jdbc:postgresql" "$OPMANAGER_DIR/conf/database_params.conf" 2>/dev/null | grep -oP ':\K\d{4,5}' | head -1)
fi
PG_PORT=${PG_PORT:-13306}

# Save DB connection info for task scripts
echo "$PG_BIN" > /tmp/opmanager_pg_bin
echo "$PG_PORT" > /tmp/opmanager_pg_port

# Wait specifically for PostgreSQL to be fully ready
echo "Waiting for PostgreSQL on port ${PG_PORT}..."
PG_ELAPSED=0
PG_TIMEOUT=180
while [ $PG_ELAPSED -lt $PG_TIMEOUT ]; do
    if ss -tlnp 2>/dev/null | grep -q ":${PG_PORT} " || netstat -tlnp 2>/dev/null | grep -q ":${PG_PORT} "; then
        echo "PostgreSQL is listening on port ${PG_PORT} after ${PG_ELAPSED}s"
        break
    fi
    sleep 5
    PG_ELAPSED=$((PG_ELAPSED + 5))
done

# Give additional time for OpManager to stabilize after DB is ready
echo "Allowing OpManager internal services to stabilize..."
sleep 30

# ============================================================
# 5. Disable mandatory password change via database
# ============================================================
echo "Disabling mandatory password change via database..."

# Enable trust auth in pg_hba.conf so we can connect without password
PG_HBA="$OPMANAGER_DIR/pgsql/data/pg_hba.conf"
if [ -f "$PG_HBA" ] && [ -f "$PG_BIN" ]; then
    if grep -q "md5" "$PG_HBA" 2>/dev/null; then
        # Only change the "all all" lines, not replication lines
        sed -i '/^local.*all.*all.*md5/s/md5/trust/' "$PG_HBA"
        sed -i '/^host.*all.*all.*127\.0\.0\.1.*md5/s/md5/trust/' "$PG_HBA"
        # Reload PostgreSQL config (must run as postgres user, not root)
        sudo -u postgres "$PGSQL_DIR/bin/pg_ctl" reload -D "$PGSQL_DIR/data" 2>/dev/null || true
        sleep 5
        echo "PostgreSQL trust auth enabled and reloaded"
    fi

    cd /tmp  # avoid "could not change directory" warnings

    # Verify DB connection works
    DB_TEST=$(sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -t -A -c "SELECT 1;" 2>/dev/null)
    if [ "$DB_TEST" = "1" ]; then
        echo "Database connection verified"

        # Disable change_pwd_on_login flag
        sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c \
            "UPDATE aaapasswordstatus SET change_pwd_on_login = false WHERE password_id = 1;" 2>/dev/null

        # Mark password as already changed (prevents the Change Password page)
        # Use SELECT...WHERE NOT EXISTS instead of ON CONFLICT for broader PostgreSQL compatibility
        sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c \
            "INSERT INTO aaauserproperty (user_id, prop_name, prop_value) SELECT 1, 'PASSWORD_CURRENT_STATUS', 'CHANGED_ON_FIRST_LOGIN' WHERE NOT EXISTS (SELECT 1 FROM aaauserproperty WHERE user_id = 1 AND prop_name = 'PASSWORD_CURRENT_STATUS');" 2>/dev/null
        sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c \
            "UPDATE aaauserproperty SET prop_value = 'CHANGED_ON_FIRST_LOGIN' WHERE user_id = 1 AND prop_name = 'PASSWORD_CURRENT_STATUS';" 2>/dev/null

        # Update password modification time to prevent expiry-triggered change
        sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c \
            "UPDATE aaapassword SET modified_time = EXTRACT(EPOCH FROM NOW()) * 1000 WHERE password_id = 1;" 2>/dev/null || true

        # Try to disable password rule enforcement at the policy level
        sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c \
            "UPDATE aaapasswordrule SET login_change_pwd = false WHERE password_rule_id IS NOT NULL;" 2>/dev/null || true

        echo "Database updated: password change requirement disabled"
    else
        echo "WARNING: Could not connect to database, password change may still be required"
    fi
else
    echo "WARNING: psql or pg_hba.conf not found, skipping DB modifications"
fi

# ============================================================
# 6. Attempt curl-based first-login + password change
# ============================================================
echo "Attempting curl-based password change..."

# Login with default credentials and follow redirects
curl -s -c /tmp/om_cookies.txt -D /tmp/om_headers.txt -L \
    -d "userName=${ADMIN_USER}&password=${DEFAULT_PASS}&domainName=local" \
    -o /tmp/om_login_resp.html \
    "${OPMANAGER_URL}/apiclient/ember/Login.jsp" 2>/dev/null

echo "Login response: $(wc -c < /tmp/om_login_resp.html 2>/dev/null || echo 0) bytes"

# Try to discover password change form from login response
FORM_ACTION=$(python3 -c "
import re, sys
try:
    with open('/tmp/om_login_resp.html') as f:
        html = f.read()
    # Look for form actions related to password change
    forms = re.findall(r'<form[^>]*action=[\"\\']([^\"\\']*)[\"\\''][^>]*>', html, re.IGNORECASE)
    for form in forms:
        if any(kw in form.lower() for kw in ['password', 'change']):
            print(form)
            sys.exit(0)
    # Also look in JavaScript for AJAX endpoints
    apis = re.findall(r'[\"\\'](/[^\"\\']*/[Cc]hange[Pp]assword[^\"\\']*)[\"\\'']', html)
    if apis:
        print(apis[0])
except:
    pass
" 2>/dev/null)

PW_CHANGED_VIA_CURL=false

# Build list of endpoints to try
ENDPOINTS="${OPMANAGER_URL}/webclient/admin/ChangePassword"
ENDPOINTS="${ENDPOINTS} ${OPMANAGER_URL}/apiclient/ember/ChangePassword.jsp"
ENDPOINTS="${ENDPOINTS} ${OPMANAGER_URL}/servlets/ChangePasswordServlet"
ENDPOINTS="${ENDPOINTS} ${OPMANAGER_URL}/api/json/admin/changePassword"
if [ -n "$FORM_ACTION" ]; then
    if [[ "$FORM_ACTION" == http* ]]; then
        ENDPOINTS="$FORM_ACTION ${ENDPOINTS}"
    else
        ENDPOINTS="${OPMANAGER_URL}${FORM_ACTION} ${ENDPOINTS}"
    fi
    echo "Discovered form action: $FORM_ACTION"
fi

for ENDPOINT in $ENDPOINTS; do
    for FIELDS in \
        "OLDPASSWORD=${DEFAULT_PASS}&NEWPASSWORD=${ADMIN_PASS}&CONFIRMPASSWORD=${ADMIN_PASS}&mailId=admin@opmanager-lab.local" \
        "oldPassword=${DEFAULT_PASS}&newPassword=${ADMIN_PASS}&confirmPassword=${ADMIN_PASS}&mailId=admin@opmanager-lab.local"; do

        PW_RESP=$(curl -s -b /tmp/om_cookies.txt -L \
            -w "\n%{http_code}" \
            -d "$FIELDS" \
            "$ENDPOINT" 2>/dev/null)
        PW_HTTP=$(echo "$PW_RESP" | tail -1)
        PW_BODY=$(echo "$PW_RESP" | sed '$d')

        echo "  POST $ENDPOINT -> HTTP $PW_HTTP"

        if [ "$PW_HTTP" = "200" ] || [ "$PW_HTTP" = "302" ] || [ "$PW_HTTP" = "303" ]; then
            if echo "$PW_BODY" | grep -qi "success\|dashboard\|home" 2>/dev/null; then
                if ! echo "$PW_BODY" | grep -qi "error\|fail\|invalid" 2>/dev/null; then
                    echo "  Password change successful via $ENDPOINT!"
                    PW_CHANGED_VIA_CURL=true
                    break 2
                fi
            fi
        fi
    done
done

# Verify credentials
echo "Verifying credentials..."
for PASS in "$ADMIN_PASS" "$DEFAULT_PASS"; do
    V_HTTP=$(curl -s -o /tmp/om_verify_body.html -w "%{http_code}" \
        -c /tmp/om_verify.txt -L \
        -d "userName=${ADMIN_USER}&password=${PASS}&domainName=local" \
        "${OPMANAGER_URL}/apiclient/ember/Login.jsp" 2>/dev/null)
    echo "  Login with password ending '${PASS: -3}': HTTP $V_HTTP"
    if [ "$V_HTTP" = "200" ] || [ "$V_HTTP" = "302" ] || [ "$V_HTTP" = "303" ]; then
        if [ "$PASS" = "$ADMIN_PASS" ]; then
            PW_CHANGED_VIA_CURL=true
        fi
        break
    fi
done

# ============================================================
# 7. Set up Firefox profile for user 'ga'
# ============================================================
echo "Setting up Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
su - ga -c "mkdir -p '$FIREFOX_PROFILE_DIR/default-release'" 2>/dev/null || \
    mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

# Create Firefox profiles.ini
cat > "$FIREFOX_PROFILE_DIR/profiles.ini" << 'FFPROFILE'
[Install4F96D1932A9F858E]
Default=default-release
Locked=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE
chown ga:ga "$FIREFOX_PROFILE_DIR/profiles.ini"

# Create user.js to configure Firefox (disable first-run dialogs)
cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to OpManager
user_pref("browser.startup.homepage", "http://localhost:8060/");
user_pref("browser.startup.page", 1);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable sidebar and other popups
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);

// Accept self-signed certs for localhost
user_pref("security.enterprise_roots.enabled", true);
USERJS
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"

# Set ownership of Firefox profile
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/OpManager.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=ManageEngine OpManager
Comment=Network Monitoring Platform
Exec=firefox http://localhost:8060/
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Network;Monitor;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/OpManager.desktop
chmod +x /home/ga/Desktop/OpManager.desktop

# ============================================================
# 8. Create utility script for OpManager database queries
# ============================================================
echo "Creating OpManager utility scripts..."

cat > /usr/local/bin/opmanager-db-query << DBEOF
#!/bin/bash
# Execute SQL query against OpManager's bundled PostgreSQL database
PG_BIN=\$(cat /tmp/opmanager_pg_bin 2>/dev/null || echo "$PG_BIN")
PG_PORT=\$(cat /tmp/opmanager_pg_port 2>/dev/null || echo "$PG_PORT")
DB_NAME="OpManagerDB"
DB_USER="postgres"

if [ -n "\$PG_BIN" ] && [ -f "\$PG_BIN" ]; then
    cd /tmp
    sudo -u postgres "\$PG_BIN" -p "\$PG_PORT" -U "\$DB_USER" "\$DB_NAME" -t -A -c "\$1" 2>/dev/null
else
    echo "PostgreSQL client not found"
    exit 1
fi
DBEOF
chmod +x /usr/local/bin/opmanager-db-query

# ============================================================
# 9. Warm-up Firefox launch (cross-cutting pattern #2)
# ============================================================
echo "Warm-up Firefox launch to clear first-run state..."
su - ga -c "export DISPLAY=:1; timeout 20 firefox --headless 'about:blank' >/dev/null 2>&1" || true
sleep 5
pkill -f firefox 2>/dev/null || true
sleep 3

# Remove profile lock files that might prevent relaunch
find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true

# ============================================================
# 10. Launch Firefox with robust retry logic (3 attempts)
# ============================================================
echo "Launching Firefox with OpManager..."

FIREFOX_READY=false
for ATTEMPT in 1 2 3; do
    echo "  Firefox launch attempt $ATTEMPT/3..."

    # Kill existing Firefox
    pkill -f firefox 2>/dev/null || true
    sleep 2

    # Remove profile lock files
    find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true

    # Launch Firefox
    su - ga -c "export DISPLAY=:1; nohup firefox '${OPMANAGER_URL}/' > /tmp/firefox_opmanager.log 2>&1 &"

    # Wait for Firefox window (up to 60s per attempt)
    FOUND=false
    for i in $(seq 1 60); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|opmanager\|ManageEngine"; then
            FOUND=true
            echo "  Firefox window detected after ${i}s"
            break
        fi
        # If Firefox process died after reasonable startup time, break early
        if [ $i -gt 15 ] && ! pgrep -f firefox > /dev/null 2>&1; then
            echo "  Firefox process died, will retry..."
            break
        fi
        sleep 1
    done

    if [ "$FOUND" = true ]; then
        sleep 3
        # Maximize Firefox window
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
            DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        fi
        FIREFOX_READY=true
        break
    fi
done

if [ "$FIREFOX_READY" = false ]; then
    echo "WARNING: Firefox failed after 3 attempts, trying last-resort launch..."
    su - ga -c "DISPLAY=:1 nohup firefox '${OPMANAGER_URL}/' > /tmp/firefox_lastresort.log 2>&1 &"
    sleep 20
    # Check one more time
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        FIREFOX_READY=true
        echo "  Firefox detected on last-resort attempt"
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
            DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        fi
    fi
fi

# ============================================================
# 11. Handle login + password change flow
# ============================================================
if [ "$FIREFOX_READY" = true ]; then
    # Wait for the login page to fully render
    echo "Waiting for page to load..."
    sleep 10

    # ============================================================
    # 11a. Automate login via xdotool
    # ============================================================
    echo "Automating login..."
    # The login page has admin pre-filled in username/password fields
    # Login button at approximately (557, 463) in 1280x720 -> (836, 695) in 1920x1080
    DISPLAY=:1 xdotool mousemove 836 695 click 1
    echo "Clicked Login button"

    # Wait for page to load after login (Change Password form + QR popup)
    sleep 15

    # ============================================================
    # 11b. Dismiss "Get alerts on your mobile" popup FIRST
    # ============================================================
    # IMPORTANT: The QR popup appears ON TOP of the Change Password form,
    # so we must dismiss it before we can interact with the form fields.
    echo "Dismissing mobile app popup if present..."
    # Try Escape key first (more reliable than coordinates for popup dismissal)
    DISPLAY=:1 xdotool key Escape
    sleep 2
    # Then click the X button at (884, 248) in 1280x720 -> (1326, 372) in 1920x1080
    DISPLAY=:1 xdotool mousemove 1326 372 click 1
    sleep 3

    # ============================================================
    # 11c. Automate mandatory password change
    # ============================================================
    echo "Automating password change..."
    # New password field at (445, 240) in 1280x720 -> (668, 360) in 1920x1080
    DISPLAY=:1 xdotool mousemove 668 360 click 1
    sleep 1
    DISPLAY=:1 xdotool type --delay 30 "Admin@123"
    sleep 1

    # Confirm password field at (445, 287) in 1280x720 -> (668, 431) in 1920x1080
    DISPLAY=:1 xdotool mousemove 668 431 click 1
    sleep 1
    DISPLAY=:1 xdotool type --delay 30 "Admin@123"
    sleep 1

    # Email field at (445, 337) in 1280x720 -> (668, 506) in 1920x1080
    DISPLAY=:1 xdotool mousemove 668 506 click 1
    sleep 1
    DISPLAY=:1 xdotool type --delay 30 "admin@opmanager-lab.local"
    sleep 1

    # Click Update Password button at (505, 410) in 1280x720 -> (758, 615) in 1920x1080
    DISPLAY=:1 xdotool mousemove 758 615 click 1
    echo "Clicked Update Password"

    # Wait for dashboard to load after password change
    sleep 15

    # ============================================================
    # 11d. Dismiss "Get started in 5 simple steps" wizard if present
    # ============================================================
    echo "Dismissing setup wizard if present..."
    # Try Escape first, then click X button
    DISPLAY=:1 xdotool key Escape
    sleep 1
    # The wizard X button at approximately (978, 241) in 1280x720 -> (1467, 362) in 1920x1080
    DISPLAY=:1 xdotool mousemove 1467 362 click 1
    sleep 2

    echo "Login and password change automation complete"
else
    echo "WARNING: Firefox window not detected - login automation skipped"
fi

# ============================================================
# 12. Final verification with retry loop
# ============================================================
echo "Final verification - ensuring dashboard is loaded..."

# Verify OpManager service state via curl (not just HTTP code)
verify_opmanager_service() {
    local body_file="/tmp/om_verify_svc.html"
    local code
    code=$(curl -s -o "$body_file" -w "%{http_code}" --max-time 10 "$OPMANAGER_URL" 2>/dev/null)
    if [ "$code" = "000" ] || [ -z "$code" ]; then
        rm -f "$body_file"; echo "down"; return
    fi
    if grep -qi "Service has not started\|Problem in starting\|maintenance" "$body_file" 2>/dev/null; then
        rm -f "$body_file"; echo "maintenance"; return
    fi
    rm -f "$body_file"; echo "running"
}

SVC_STATE=$(verify_opmanager_service)
echo "OpManager service state: $SVC_STATE"

# If service is in maintenance, wait longer and retry
if [ "$SVC_STATE" = "maintenance" ] || [ "$SVC_STATE" = "down" ]; then
    echo "Service not healthy, waiting 60s and rechecking..."
    sleep 60
    SVC_STATE=$(verify_opmanager_service)
    echo "OpManager service state after wait: $SVC_STATE"

    if [ "$SVC_STATE" != "running" ]; then
        echo "Still not healthy, attempting restart..."
        "$OPMANAGER_DIR/bin/shutdown.sh" 2>/dev/null || true
        sleep 10
        pkill -f "$OPMANAGER_DIR/jre/bin/java" 2>/dev/null || true
        sleep 5
        systemctl start OpManager.service 2>/dev/null || {
            cd "$OPMANAGER_DIR/bin" && nohup ./run.sh > /tmp/opmanager_restart_post.log 2>&1 &
        }
        wait_for_opmanager 300
        sleep 15
    fi
fi

if [ "$FIREFOX_READY" = true ]; then
    # Navigate to OpManager base URL to verify state
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8060/"
    DISPLAY=:1 xdotool key Return
    sleep 8

    # Check window title for state detection
    TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    echo "Window title after navigation: $TITLE"

    # If Change Password page is detected, retry the password automation
    if echo "$TITLE" | grep -qi "change.password\|update.password"; then
        echo "Change Password page still showing, retrying automation..."

        # Re-apply DB fix
        if [ -f "$PG_BIN" ]; then
            cd /tmp
            sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c \
                "UPDATE aaapasswordstatus SET change_pwd_on_login = false WHERE password_id = 1;" 2>/dev/null || true
            sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c \
                "UPDATE aaapasswordrule SET login_change_pwd = false WHERE password_rule_id IS NOT NULL;" 2>/dev/null || true
        fi

        # Dismiss QR popup
        DISPLAY=:1 xdotool key Escape
        sleep 2
        DISPLAY=:1 xdotool mousemove 1326 372 click 1
        sleep 2

        # Fill password form
        DISPLAY=:1 xdotool mousemove 668 360 click 1
        sleep 0.5
        DISPLAY=:1 xdotool key ctrl+a
        DISPLAY=:1 xdotool type --delay 30 "${ADMIN_PASS}"
        sleep 0.5
        DISPLAY=:1 xdotool mousemove 668 431 click 1
        sleep 0.5
        DISPLAY=:1 xdotool key ctrl+a
        DISPLAY=:1 xdotool type --delay 30 "${ADMIN_PASS}"
        sleep 0.5
        DISPLAY=:1 xdotool mousemove 668 506 click 1
        sleep 0.5
        DISPLAY=:1 xdotool key ctrl+a
        DISPLAY=:1 xdotool type --delay 30 "admin@opmanager-lab.local"
        sleep 0.5
        DISPLAY=:1 xdotool mousemove 758 615 click 1
        sleep 10

        # Dismiss wizard
        DISPLAY=:1 xdotool key Escape
        sleep 1
        DISPLAY=:1 xdotool mousemove 1467 362 click 1
        sleep 2

        # Navigate to dashboard
        DISPLAY=:1 xdotool key ctrl+l
        sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8060/"
        DISPLAY=:1 xdotool key Return
        sleep 8
    fi

    # Dismiss any remaining popups
    DISPLAY=:1 xdotool key Escape
    sleep 1
    DISPLAY=:1 xdotool key Escape
    sleep 1
fi

# Take verification screenshot
DISPLAY=:1 scrot /tmp/post_setup_verify.png 2>/dev/null || true

# Final window title check
TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
echo "Final state - Window title: $TITLE"

# Save state for task scripts
echo "$FIREFOX_READY" > /tmp/opmanager_firefox_ready
echo "$PW_CHANGED_VIA_CURL" > /tmp/opmanager_pw_changed

echo ""
echo "=== ManageEngine OpManager Setup Complete ==="
echo ""
echo "OpManager is running at: $OPMANAGER_URL"
echo "Install directory: $OPMANAGER_DIR"
echo ""
echo "Login Credentials:"
echo "  Username: ${ADMIN_USER}"
echo "  Password: ${ADMIN_PASS}"
echo ""
echo "SNMP Agent: $(systemctl is-active snmpd 2>/dev/null || echo 'running')"
echo "  Community: public"
echo "  Port: 161"
echo ""
echo "Real monitoring data available:"
echo "  - SNMP system metrics (CPU, memory, disk, interfaces)"
echo "  - Running processes (sshd, snmpd, java)"
echo "  - Network interface statistics"
echo ""
echo "Database access: opmanager-db-query 'SELECT COUNT(*) FROM ...'"
echo ""
