#!/bin/bash
# Aerobridge Setup Script (post_start hook)
# Starts the Django server and launches Firefox to the admin panel

set -e

echo "=== Setting up Aerobridge ==="

# ============================================================
# 1. Wait for desktop to be ready
# ============================================================
sleep 5

# ============================================================
# 2. Configure Firefox profile to suppress first-run dialogs
#    CRITICAL: Ubuntu Firefox snap stores data in:
#    /home/ga/snap/firefox/common/.mozilla/firefox/
#    Create profile in BOTH the snap path and standard path.
# ============================================================
echo "Configuring Firefox profile..."

# Write user.js to suppress all first-run dialogs
write_ff_profile() {
    local profile_dir="$1"
    mkdir -p "${profile_dir}"
    cat > "${profile_dir}/user.js" << 'USERJS'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.startup.page", 0);
user_pref("extensions.autoDisableScopes", 15);
user_pref("extensions.enabledScopes", 5);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("browser.safebrowsing.passwords.enabled", false);
USERJS
}

write_ff_profiles_ini() {
    local ini_dir="$1"
    cat > "${ini_dir}/profiles.ini" << 'PROFILEINI'
[Profile0]
Name=aerobridge
IsRelative=1
Path=aerobridge.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
PROFILEINI
}

# Create in snap path (primary — where Ubuntu Firefox snap actually reads)
SNAP_FF_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
mkdir -p "${SNAP_FF_DIR}"
write_ff_profile "${SNAP_FF_DIR}/aerobridge.profile"
write_ff_profiles_ini "${SNAP_FF_DIR}"
chown -R ga:ga /home/ga/snap/firefox/
echo "Firefox snap profile configured at ${SNAP_FF_DIR}/aerobridge.profile"

# Also create at standard path as fallback
mkdir -p /home/ga/.mozilla/firefox
write_ff_profile "/home/ga/.mozilla/firefox/aerobridge.profile"
write_ff_profiles_ini "/home/ga/.mozilla/firefox"
chown -R ga:ga /home/ga/.mozilla
echo "Firefox standard profile configured."

# ============================================================
# 3. Start Aerobridge Django development server via systemd
#    Using a systemd unit for reliable service management
# ============================================================
echo "Starting Aerobridge Django server..."

# Create systemd service unit for reliable daemonization
cat > /etc/systemd/system/aerobridge.service << 'UNITEOF'
[Unit]
Description=Aerobridge Drone Management Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/aerobridge
EnvironmentFile=/opt/aerobridge/.env
ExecStart=/opt/aerobridge_venv/bin/python manage.py runserver 0.0.0.0:8000
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/aerobridge_server.log
StandardError=append:/var/log/aerobridge_server.log

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable aerobridge
systemctl start aerobridge
SERVER_PID=$(systemctl show aerobridge --property=MainPID --value 2>/dev/null || echo "unknown")
echo "Aerobridge service started (PID: ${SERVER_PID})"

# ============================================================
# 4. Wait for Aerobridge server to be ready (poll with timeout)
# ============================================================
echo "Waiting for Aerobridge server to be ready..."
timeout=90
elapsed=0
while [ $elapsed -lt $timeout ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:8000/admin/" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "Aerobridge is ready after ${elapsed}s (HTTP ${HTTP_CODE})"
        break
    fi
    sleep 3
    elapsed=$((elapsed + 3))
    echo "  Waiting... ${elapsed}s (HTTP ${HTTP_CODE})"
done

if [ $elapsed -ge $timeout ]; then
    echo "WARNING: Aerobridge readiness check timed out after ${timeout}s"
    echo "Last 20 lines of server log:"
    tail -20 /var/log/aerobridge_server.log 2>/dev/null || true
fi

# ============================================================
# 5. Open Firefox to Aerobridge admin panel
#    Using setsid + XAUTHORITY pattern for X11 display access
#    (Pattern 18, 20: setsid and XAUTHORITY for cross-user X11)
# ============================================================
echo "Opening Firefox to Aerobridge admin panel..."

# Wait for X11 to be available
sleep 3

# Launch Firefox as user 'ga' with the configured profile
# Use --no-remote to force new instance; remove snap lock files too
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock
su - ga -c "rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock; DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/' &"

sleep 5

# ============================================================
# 6. Report status
# ============================================================
echo ""
echo "=== Aerobridge Setup Complete ==="
echo "Server: http://localhost:8000"
echo "Admin panel: http://localhost:8000/admin/"
echo "Admin credentials: admin / adminpass123"
echo "Log: /var/log/aerobridge_server.log"
echo "Database: /opt/aerobridge/aerobridge.sqlite3"

# Quick database status check
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 -c "
import os, sys
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
# Load env vars
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip(\"'\").strip('\"'))
import django
django.setup()
try:
    from registry.models import Aircraft, Company, Person
    print(f'Aircraft: {Aircraft.objects.count()}')
    print(f'Companies: {Company.objects.count()}')
    print(f'Persons: {Person.objects.count()}')
except Exception as e:
    print(f'DB check error: {e}')
" 2>/dev/null || echo "DB status check skipped"

echo "=== Setup complete ==="
