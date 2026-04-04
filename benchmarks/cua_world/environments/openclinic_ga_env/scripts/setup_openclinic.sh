#!/bin/bash
# OpenClinic GA Setup Script (post_start hook)
# Waits for background install to complete, starts OpenClinic, seeds data, launches Firefox.
# Access: http://localhost:10088/openclinic
# Default credentials: username=4, password=openclinic (shown on login page)
#
# OpenClinic GA MySQL details (discovered from install):
#   Binary: /opt/openclinic/mysql5/bin/mysql
#   Socket: /tmp/mysql5.sock
#   User: root (no password)
#   Databases: ocadmin_dbo (patients), openclinic_dbo (clinical data)

echo "=== Setting up OpenClinic GA (post_start) ==="

# Wait for desktop
sleep 5

# ---------------------------------------------------------------
# Wait for background installation to complete
# ---------------------------------------------------------------
echo "Waiting for background installation to complete..."
TIMEOUT=600
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    if [ -f /tmp/openclinic_install_done ]; then
        echo "Background installation complete after ${ELAPSED}s"
        break
    fi
    if [ -f /tmp/openclinic_install_failed ]; then
        echo "ERROR: Background installation failed!"
        cat /home/ga/env_setup_openclinic_download.log 2>/dev/null | tail -30
        exit 1
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    if [ $((ELAPSED % 60)) -eq 0 ]; then
        echo "  Still waiting for install... ${ELAPSED}s"
        tail -3 /home/ga/env_setup_openclinic_download.log 2>/dev/null || true
    fi
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: Installation timed out after ${TIMEOUT}s"
    cat /home/ga/env_setup_openclinic_download.log 2>/dev/null | tail -30
    exit 1
fi

if [ ! -d /opt/openclinic ]; then
    echo "ERROR: /opt/openclinic not found after install"
    exit 1
fi

echo "OpenClinic GA installed at /opt/openclinic"

# ---------------------------------------------------------------
# Start OpenClinic GA service
# ---------------------------------------------------------------
echo "Starting OpenClinic GA..."
if [ -f /opt/openclinic/restart_openclinic ]; then
    chmod +x /opt/openclinic/restart_openclinic
    /opt/openclinic/restart_openclinic 2>/dev/null || true
elif [ -f /opt/openclinic/start_openclinic ]; then
    chmod +x /opt/openclinic/start_openclinic
    /opt/openclinic/start_openclinic 2>/dev/null || true
fi

# Wait for OpenClinic to become available
OPENCLINIC_URL="http://localhost:10088/openclinic"
echo "Waiting for OpenClinic GA to be ready..."
TIMEOUT=300
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$OPENCLINIC_URL" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "OpenClinic GA is ready after ${ELAPSED}s (HTTP $HTTP_CODE)"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ $((ELAPSED % 30)) -eq 0 ]; then
        echo "  Still waiting... ${ELAPSED}s (HTTP $HTTP_CODE)"
    fi
done

# ---------------------------------------------------------------
# MySQL connection helper (root, no password, socket /tmp/mysql5.sock)
# ---------------------------------------------------------------
MYSQL_BIN="/opt/openclinic/mysql5/bin/mysql"
MYSQL_SOCKET="/tmp/mysql5.sock"

admin_query() { $MYSQL_BIN -S "$MYSQL_SOCKET" -u root ocadmin_dbo -N -e "$1" 2>/dev/null; }
clinical_query() { $MYSQL_BIN -S "$MYSQL_SOCKET" -u root openclinic_dbo -N -e "$1" 2>/dev/null; }

# Wait for MySQL to be accessible
echo "Waiting for MySQL to be accessible..."
for i in $(seq 1 30); do
    if admin_query "SELECT 1" >/dev/null 2>&1; then
        echo "MySQL is accessible (attempt $i)"
        PATIENT_COUNT=$(admin_query "SELECT COUNT(*) FROM adminview" 2>/dev/null || echo "unknown")
        echo "Initial patient count: $PATIENT_COUNT"
        break
    fi
    sleep 3
    echo "  Waiting for MySQL... attempt $i"
done

# Load seed data (uses USE statements to switch between ocadmin_dbo and openclinic_dbo)
if [ -f /workspace/config/seed_data.sql ]; then
    echo "Loading seed data (patients + clinical catalog)..."
    $MYSQL_BIN -S "$MYSQL_SOCKET" -u root < /workspace/config/seed_data.sql 2>&1 | grep -v "^$" | head -20 || true
    # Verify seeding
    PT_COUNT=$(admin_query "SELECT COUNT(*) FROM adminview WHERE personid BETWEEN 10001 AND 10010" 2>/dev/null || echo "?")
    echo "Seeded patients (ID 10001-10010): $PT_COUNT"
fi

# ---------------------------------------------------------------
# Create helper script for task_utils.sh
# ---------------------------------------------------------------
cat > /usr/local/bin/openclinic-query << 'QEOF'
#!/bin/bash
# Query OpenClinic GA MySQL database
# Usage: openclinic-query DBNAME "SQL QUERY"
MYSQL=/opt/openclinic/mysql5/bin/mysql
DB="${1:-ocadmin_dbo}"
QUERY="$2"
$MYSQL -S /tmp/mysql5.sock -u root "$DB" -N -e "$QUERY" 2>/dev/null
QEOF
chmod +x /usr/local/bin/openclinic-query

# ---------------------------------------------------------------
# Configure Firefox popup settings
# Firefox on this VM is a snap package:
#   profile lives at ~/snap/firefox/common/.mozilla/firefox/
# ---------------------------------------------------------------
echo "Configuring Firefox..."

# Warm-up Firefox to create profile directory
su - ga -c "DISPLAY=:1 firefox --headless about:blank &" 2>/dev/null || true
sleep 12
pkill -9 -f "firefox" 2>/dev/null || true
sleep 3

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
    echo "  Wrote user.js to: $profile_dir"
}

# Handle snap Firefox profile (primary path)
SNAP_FF_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
if [ -d "$SNAP_FF_BASE" ]; then
    echo "Found snap Firefox profile base: $SNAP_FF_BASE"
    FF_PROFILE_DIR=$(find "$SNAP_FF_BASE" -name "*.default*" -maxdepth 1 -type d 2>/dev/null | head -1)
    if [ -z "$FF_PROFILE_DIR" ]; then
        FF_PROFILE_DIR=$(find "$SNAP_FF_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
    fi
    if [ -n "$FF_PROFILE_DIR" ]; then
        write_firefox_userjs "$FF_PROFILE_DIR"
    else
        # Create default snap profile
        FF_PROFILE_DIR="$SNAP_FF_BASE/default"
        write_firefox_userjs "$FF_PROFILE_DIR"
        cat > "$SNAP_FF_BASE/profiles.ini" << 'PROFEOF'
[General]
StartWithLastProfile=1

[Profile0]
Name=default
IsRelative=1
Path=default
Default=1
PROFEOF
    fi
    chown -R ga:ga /home/ga/snap/firefox 2>/dev/null || true
else
    echo "Snap Firefox not yet initialized, creating dirs..."
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
    chown -R ga:ga /home/ga/snap 2>/dev/null || true
fi

# Also write to regular ~/.mozilla/firefox as fallback
FF_REG_PROFILE_DIR=$(find /home/ga/.mozilla/firefox -name "*.default*" -maxdepth 1 -type d 2>/dev/null | head -1)
if [ -n "$FF_REG_PROFILE_DIR" ]; then
    write_firefox_userjs "$FF_REG_PROFILE_DIR"
    chown -R ga:ga /home/ga/.mozilla 2>/dev/null || true
fi

# ---------------------------------------------------------------
# Launch Firefox with OpenClinic GA
# ---------------------------------------------------------------
echo "Launching Firefox with OpenClinic GA..."
su - ga -c "DISPLAY=:1 firefox '$OPENCLINIC_URL' > /tmp/firefox_openclinic.log 2>&1 &"
sleep 8

# Focus and maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take screenshot
DISPLAY=:1 scrot /tmp/openclinic_setup.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/openclinic_setup.png 2>/dev/null || true

echo ""
echo "=== OpenClinic GA setup complete ==="
echo "Access URL: http://localhost:10088/openclinic"
echo "Login: username=4 (or 'openclinic'), password=openclinic"
echo ""
echo "MySQL access:"
echo "  /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root ocadmin_dbo"
echo "  /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root openclinic_dbo"
