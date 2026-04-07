#!/bin/bash
# OpenClinic GA Setup Script (post_start hook)
# Starts OpenClinic services from a fully installed pre_start image, seeds data,
# and lands Firefox on a visible login page.

set -euo pipefail

echo "=== Setting up OpenClinic GA (post_start) ==="
sleep 5

INSTALL_MARKER=/tmp/openclinic_install_done
FAIL_MARKER=/tmp/openclinic_install_failed
OPENCLINIC_ROOT=/opt/openclinic
OPENCLINIC_URL="http://localhost:10088/openclinic"
MYSQL_BIN="$OPENCLINIC_ROOT/mysql5/bin/mysql"
MYSQL_SOCKET="/tmp/mysql5.sock"

if [ -f "$FAIL_MARKER" ]; then
    echo "ERROR: Previous install attempt failed"
    tail -50 /home/ga/env_setup_openclinic_download.log 2>/dev/null || true
    exit 1
fi

if [ ! -d "$OPENCLINIC_ROOT" ] || [ ! -x "$MYSQL_BIN" ]; then
    echo "ERROR: OpenClinic is not installed at $OPENCLINIC_ROOT"
    ls -la /opt || true
    exit 1
fi

touch "$INSTALL_MARKER"
echo "OpenClinic GA installed at $OPENCLINIC_ROOT"

# Function to clean up stale processes and PID/lock files
cleanup_stale_state() {
    echo "Cleaning up stale processes and lock files..."
    # Kill stale Java/Tomcat processes
    pkill -f "catalina" 2>/dev/null || true
    pkill -f "tomcat" 2>/dev/null || true
    # Kill stale MySQL processes
    pkill -f "mysqld.*openclinic" 2>/dev/null || true
    sleep 3
    # Force kill if still alive
    pkill -9 -f "catalina" 2>/dev/null || true
    pkill -9 -f "mysqld.*openclinic" 2>/dev/null || true
    sleep 2
    # Remove stale PID files
    find "$OPENCLINIC_ROOT" -name "*.pid" -delete 2>/dev/null || true
    # Remove stale MySQL socket
    rm -f "$MYSQL_SOCKET" 2>/dev/null || true
    # Remove Tomcat PID file
    rm -f "$OPENCLINIC_ROOT/tomcat8/bin/catalina.pid" 2>/dev/null || true
    echo "Cleanup done"
}

# Function to start OpenClinic services
start_openclinic_services() {
    if [ -f "$OPENCLINIC_ROOT/restart_openclinic" ]; then
        chmod +x "$OPENCLINIC_ROOT/restart_openclinic"
        "$OPENCLINIC_ROOT/restart_openclinic" 2>/dev/null || true
    elif [ -f "$OPENCLINIC_ROOT/start_openclinic" ]; then
        chmod +x "$OPENCLINIC_ROOT/start_openclinic"
        "$OPENCLINIC_ROOT/start_openclinic" 2>/dev/null || true
    else
        echo "ERROR: No OpenClinic start script found"
        find "$OPENCLINIC_ROOT" -maxdepth 2 -type f | sed -n '1,80p'
        exit 1
    fi
}

# Function to wait for OpenClinic HTTP readiness
wait_for_openclinic_http() {
    local timeout=${1:-300}
    local elapsed=0
    local http_code=000
    while [ "$elapsed" -lt "$timeout" ]; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$OPENCLINIC_URL" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
            echo "OpenClinic GA is ready after ${elapsed}s (HTTP $http_code)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  Still waiting... ${elapsed}s (HTTP $http_code)"
        fi
    done
    echo "OpenClinic not ready after ${timeout}s (HTTP $http_code)"
    return 1
}

# First attempt: clean up stale state, then start
cleanup_stale_state

echo "Starting OpenClinic GA services (attempt 1)..."
start_openclinic_services

echo "Waiting for OpenClinic GA to be ready..."
if ! wait_for_openclinic_http 300; then
    echo "First attempt failed. Retrying with full cleanup..."
    cleanup_stale_state
    sleep 5
    echo "Starting OpenClinic GA services (attempt 2)..."
    start_openclinic_services

    if ! wait_for_openclinic_http 300; then
        echo "ERROR: OpenClinic did not become reachable after 2 attempts"
        ps -ef | grep -Ei 'openclinic|tomcat|java|mysql' | grep -v grep || true
        ss -ltnp | grep -E '10088|13306|3306|8080' || true
        tail -80 "$OPENCLINIC_ROOT/tomcat8/logs/catalina.out" 2>/dev/null || true
        exit 1
    fi
fi

admin_query() { "$MYSQL_BIN" -S "$MYSQL_SOCKET" -u root ocadmin_dbo -N -e "$1" 2>/dev/null; }
clinical_query() { "$MYSQL_BIN" -S "$MYSQL_SOCKET" -u root openclinic_dbo -N -e "$1" 2>/dev/null; }

echo "Waiting for MySQL to be accessible..."
for i in $(seq 1 30); do
    if admin_query "SELECT 1" >/dev/null 2>&1; then
        PATIENT_COUNT=$(admin_query "SELECT COUNT(*) FROM adminview" 2>/dev/null || echo "unknown")
        echo "MySQL is accessible (attempt $i); current patient count: $PATIENT_COUNT"
        break
    fi
    sleep 3
    echo "  Waiting for MySQL... attempt $i"
done

if ! admin_query "SELECT 1" >/dev/null 2>&1; then
    echo "ERROR: MySQL never became accessible"
    ps -ef | grep -Ei 'mysql|mysqld' | grep -v grep || true
    exit 1
fi

if [ -f /workspace/config/seed_data.sql ]; then
    echo "Loading seed data..."
    "$MYSQL_BIN" -S "$MYSQL_SOCKET" -u root < /workspace/config/seed_data.sql 2>&1 | grep -v "^$" | head -20 || true
    PT_COUNT=$(admin_query "SELECT COUNT(*) FROM adminview WHERE personid BETWEEN 10001 AND 10010" 2>/dev/null || echo "?")
    echo "Seeded patients (ID 10001-10010): $PT_COUNT"
fi

cat > /usr/local/bin/openclinic-query << 'QEOF'
#!/bin/bash
MYSQL=/opt/openclinic/mysql5/bin/mysql
DB="${1:-ocadmin_dbo}"
QUERY="$2"
"$MYSQL" -S /tmp/mysql5.sock -u root "$DB" -N -e "$QUERY" 2>/dev/null
QEOF
chmod +x /usr/local/bin/openclinic-query

echo "Configuring Firefox..."

write_firefox_userjs() {
    local profile_dir="$1"
    mkdir -p "$profile_dir"
    cat > "${profile_dir}/user.js" << 'USERJS'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.page", 1);
user_pref("browser.startup.homepage", "http://localhost:10088/openclinic");
user_pref("signon.rememberSignons", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.download.manager.showWhenStarting", false);
user_pref("browser.privatebrowsing.autostart", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("extensions.pocket.enabled", false);
user_pref("dom.disable_open_during_load", false);
user_pref("privacy.popups.showBrowserMessage", false);
user_pref("dom.popup_maximum", 0);
user_pref("dom.popup_allowed_events", "change click dblclick auxclick mousedown mouseup pointerdown pointerup notificationclick reset submit touchend touchstart");
USERJS
}

SNAP_FF_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
mkdir -p "$SNAP_FF_BASE/default"
write_firefox_userjs "$SNAP_FF_BASE/default"
cat > "$SNAP_FF_BASE/profiles.ini" << 'PROFEOF'
[General]
StartWithLastProfile=1

[Profile0]
Name=default
IsRelative=1
Path=default
Default=1
PROFEOF
mkdir -p /home/ga/.mozilla/firefox
chown -R ga:ga /home/ga/snap /home/ga/.mozilla 2>/dev/null || true

source /workspace/scripts/task_utils.sh
ensure_openclinic_browser "$OPENCLINIC_URL"
take_screenshot /tmp/openclinic_setup.png

echo ""
echo "=== OpenClinic GA setup complete ==="
echo "Access URL: $OPENCLINIC_URL"
echo "Login: username=4 (or 'openclinic'), password=openclinic"
echo ""
echo "MySQL access:"
echo "  /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root ocadmin_dbo"
echo "  /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root openclinic_dbo"
