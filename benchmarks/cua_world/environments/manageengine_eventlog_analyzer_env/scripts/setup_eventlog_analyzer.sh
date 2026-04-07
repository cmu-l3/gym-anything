#!/bin/bash
# ManageEngine EventLog Analyzer Setup Script (post_start hook)
#
# This script runs INSIDE the QEMU VM after the desktop starts.
#
# IMPORTANT: Uses background continuation pattern (#23) for BOTH install AND service start,
# because the total setup time (download ~10 min + install + ELA start ~5 min + password reset)
# exceeds the 600-second post_start hook timeout enforced by env.py.
#
# Flow:
#   pre_start  → starts background download+install → returns in <2 min
#   post_start → configures Firefox profile, starts background ELA-setup script → returns in <60s
#   pre_task   → waits for ELA to be ready (uses wait_for_eventlog_analyzer with 900s timeout)
#
# Default credentials: admin / admin
# Web UI: http://localhost:8095/event/index.do

echo "=== Setting up ManageEngine EventLog Analyzer (post_start) ==="

ELA_HOME="/opt/ManageEngine/EventLog"

# =====================================================
# Step 1: Configure Firefox profile (quick - file writes only)
# This must happen here so Firefox doesn't show first-run dialogs when launched by pre_task.
# =====================================================
echo "Configuring Firefox profile..."

# Fix snap Firefox data directory permissions (snap requires version-specific dir)
SNAP_FF_VERSION=$(snap list firefox 2>/dev/null | awk '/firefox/{print $3}')
if [ -n "$SNAP_FF_VERSION" ]; then
    mkdir -p "/home/ga/snap/firefox/$SNAP_FF_VERSION"
    chown -R ga:ga /home/ga/snap/firefox 2>/dev/null || true
fi

if [ -d "/home/ga/snap/firefox" ]; then
    echo "Detected snap Firefox"
    FIREFOX_PROFILE_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
else
    FIREFOX_PROFILE_BASE="/home/ga/.mozilla/firefox"
fi

mkdir -p "$FIREFOX_PROFILE_BASE/ela.profile"

cat > "$FIREFOX_PROFILE_BASE/profiles.ini" << 'FFPROFILE'
[Install4F96D1932A9F858E]
Default=ela.profile
Locked=1

[Profile0]
Name=ela-profile
IsRelative=1
Path=ela.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE

cat > "$FIREFOX_PROFILE_BASE/ela.profile/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.homepage", "http://localhost:8095/event/index.do");
user_pref("browser.startup.page", 1);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.uitour.enabled", false);
USERJS

# Fix ownership of entire snap Firefox tree (post_start runs as root, so
# mkdir -p above creates parent dirs owned by root — snap Firefox then
# fails with "Profile Missing" because it can't read/write its own dirs).
chown -R ga:ga /home/ga/snap 2>/dev/null || true
chown -R ga:ga "$FIREFOX_PROFILE_BASE"
echo "Firefox profile configured at $FIREFOX_PROFILE_BASE"

# =====================================================
# Step 2: Create desktop shortcut
# =====================================================
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/EventLogAnalyzer.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=ManageEngine EventLog Analyzer
Comment=SIEM Log Management
Exec=firefox http://localhost:8095/event/index.do
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Network;Security;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/EventLogAnalyzer.desktop
chmod +x /home/ga/Desktop/EventLogAnalyzer.desktop

# Mark desktop file as trusted so GNOME doesn't show "Untrusted Desktop File" dialog
su - ga -c "dbus-launch gio set /home/ga/Desktop/EventLogAnalyzer.desktop metadata::trusted true" 2>/dev/null || true

# =====================================================
# Step 3: Write background ELA setup script
# Does all time-consuming work: wait for install, start ELA, reset password.
# pre_task hooks (setup_task.sh) will call wait_for_eventlog_analyzer to wait for readiness.
# =====================================================
cat > /tmp/ela_setup_bg.sh << 'BGEOF'
#!/bin/bash
ELA_HOME="/opt/ManageEngine/EventLog"
INSTALL_MARKER="/tmp/ela_install_complete.marker"
SERVICE_MARKER="/tmp/ela_service_ready.marker"
SETUP_LOG="/tmp/ela_setup_bg.log"
ELA_PORT="8095"
ELA_URL="http://localhost:${ELA_PORT}/event/index.do"

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$SETUP_LOG"; }
log "=== Background ELA Setup Started ==="

# Check if ELA is already installed (checkpoint recovery or repeated run).
if [ -d "$ELA_HOME/bin" ]; then
    log "ELA already installed at $ELA_HOME/bin"
    echo "OK" > "$INSTALL_MARKER"
elif [ ! -f "$INSTALL_MARKER" ] && [ -f "/opt/setup/ela_install_bg.sh" ]; then
    # Checkpoint recovery scenario: the install script exists (written by pre_start)
    # but neither the install marker nor the install directory exists. The background
    # installer from pre_start was killed by VM reboot. Re-run it synchronously.
    log "No ELA install found. Re-running installer (checkpoint recovery)..."
    bash /opt/setup/ela_install_bg.sh
    log "Installer completed (re-run)"
fi

# If the installer is running in background (normal non-cached flow), wait for it
if [ ! -d "$ELA_HOME/bin" ] && [ ! -f "$INSTALL_MARKER" ]; then
    log "Waiting for install marker..."
    WAIT_ELAPSED=0
    while [ ! -f "$INSTALL_MARKER" ]; do
        if [ -d "$ELA_HOME/bin" ]; then
            log "ELA install directory appeared, marking as complete"
            echo "OK" > "$INSTALL_MARKER"
            break
        fi
        sleep 15
        WAIT_ELAPSED=$((WAIT_ELAPSED + 15))
        log "  Waiting for install... ${WAIT_ELAPSED}s"
        if [ $WAIT_ELAPSED -ge 1800 ]; then
            log "ERROR: Install timed out after 1800s"
            echo "INSTALL_TIMEOUT" > "$SERVICE_MARKER"
            exit 1
        fi
    done
fi

MARKER_CONTENT=$(cat "$INSTALL_MARKER" 2>/dev/null)
if [ "$MARKER_CONTENT" != "OK" ]; then
    log "ERROR: Install failed (marker: $MARKER_CONTENT)"
    echo "INSTALL_FAILED:$MARKER_CONTENT" > "$SERVICE_MARKER"
    exit 1
fi
log "Install complete."

if [ ! -d "$ELA_HOME/bin" ]; then
    log "ERROR: $ELA_HOME/bin not found after install"
    echo "INSTALL_PATH_MISSING" > "$SERVICE_MARKER"
    exit 1
fi

# Kill any stale instances and start ELA
pkill -f "WrapperJVMMain" 2>/dev/null || true
pkill -f "java.*EventLog" 2>/dev/null || true
sleep 3
log "Starting ELA service..."
(cd "$ELA_HOME/bin" && nohup bash app_ctl.sh run > /tmp/ela_start.log 2>&1 &)

# Wait for ELA web UI (up to 6 minutes)
log "Waiting for ELA web UI on port $ELA_PORT..."
ELAPSED=0
READY=false
while [ $ELAPSED -lt 360 ]; do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$ELA_URL" 2>/dev/null || echo "000")
    if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ] || [ "$HTTP" = "303" ]; then
        log "ELA ready after ${ELAPSED}s (HTTP $HTTP)"
        READY=true
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    log "  Waiting... ${ELAPSED}s (HTTP $HTTP)"
done

if [ "$READY" != "true" ]; then
    log "WARNING: ELA web UI timeout after 360s - continuing anyway"
fi
sleep 5

# Stop ELA before running resetPwd.sh (notes: "Must stop ELA first")
log "Stopping ELA for password reset..."
pkill -f "WrapperJVMMain" 2>/dev/null || true
pkill -f "java.*EventLog" 2>/dev/null || true
sleep 10
# Verify it's fully stopped
while pgrep -f "WrapperJVMMain" > /dev/null 2>&1; do
    log "  Waiting for ELA to stop..."
    pkill -9 -f "WrapperJVMMain" 2>/dev/null || true
    pkill -9 -f "java.*EventLog" 2>/dev/null || true
    sleep 5
done
log "ELA stopped."

# Reset admin password to 'admin' via resetPwd.sh
log "Resetting admin password via resetPwd.sh..."
(cd "$ELA_HOME/troubleshooting" && bash resetPwd.sh >> "$SETUP_LOG" 2>&1)
log "Password reset done"
sleep 3

# Start ELA with retry logic (sometimes first start after reset fails)
log "Starting ELA after password reset..."
ATTEMPT=0
MAX_ATTEMPTS=2
ELA_STARTED=false
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    log "Start attempt $ATTEMPT of $MAX_ATTEMPTS..."
    (cd "$ELA_HOME/bin" && nohup bash app_ctl.sh run >> /tmp/ela_start.log 2>&1 &)

    # Wait for ELA to come up (up to 5 minutes per attempt)
    ELAPSED=0
    while [ $ELAPSED -lt 300 ]; do
        HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$ELA_URL" 2>/dev/null || echo "000")
        if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then
            log "ELA started after ${ELAPSED}s (attempt $ATTEMPT)"
            ELA_STARTED=true
            break
        fi
        # Check if wrapper crashed ("System halted" in the log)
        if [ $ELAPSED -ge 60 ] && ! pgrep -f "WrapperJVMMain" > /dev/null 2>&1; then
            log "WARNING: ELA process died during startup (attempt $ATTEMPT)"
            break
        fi
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done

    if [ "$ELA_STARTED" = "true" ]; then
        break
    fi

    # Cleanup for retry
    log "Retrying ELA start..."
    pkill -9 -f "WrapperJVMMain" 2>/dev/null || true
    pkill -9 -f "java.*EventLog" 2>/dev/null || true
    sleep 10
done

if [ "$ELA_STARTED" != "true" ]; then
    log "WARNING: ELA failed to start after $MAX_ATTEMPTS attempts"
fi
sleep 5

# Configure rsyslog
log "Configuring rsyslog..."
cat > /etc/rsyslog.d/10-eventlog-analyzer.conf << 'RSYSLOGEOF'
*.* @127.0.0.1:514
RSYSLOGEOF
systemctl restart rsyslog 2>/dev/null || service rsyslog restart 2>/dev/null || true

# Generate log activity
log "Generating log activity..."
for i in {1..5}; do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
        -o PasswordAuthentication=yes invaliduser@127.0.0.1 "echo test" </dev/null 2>/dev/null || true
    sleep 1
done
su - ga -c "sudo ls /root 2>&1" || true
logger -t security "EventLog Analyzer setup: monitoring started on $(hostname)" 2>/dev/null || true

# Copy real syslog data for import tasks
log "Preparing log samples..."
mkdir -p /home/ga/log_samples
[ -f /var/log/syslog ]   && cp /var/log/syslog   /home/ga/log_samples/system.log && chmod 644 /home/ga/log_samples/system.log
[ -f /var/log/auth.log ] && cp /var/log/auth.log  /home/ga/log_samples/auth.log   && chmod 644 /home/ga/log_samples/auth.log
[ -f /var/log/kern.log ] && cp /var/log/kern.log  /home/ga/log_samples/kern.log   && chmod 644 /home/ga/log_samples/kern.log
chown -R ga:ga /home/ga/log_samples

log "=== Background ELA Setup Complete ==="
echo "OK" > "$SERVICE_MARKER"
log "Service ready marker written: $SERVICE_MARKER"
BGEOF

chmod +x /tmp/ela_setup_bg.sh

# =====================================================
# Step 4: Start background ELA setup and return immediately
# =====================================================
echo "Starting background ELA service setup..."
nohup bash /tmp/ela_setup_bg.sh > /tmp/ela_setup_nohup.log 2>&1 &
BG_PID=$!
echo "Background setup PID: $BG_PID"
echo "Setup log: /tmp/ela_setup_bg.log"
echo "Service ready marker: /tmp/ela_service_ready.marker"
echo ""
echo "post_start returning immediately."
echo "pre_task hooks will call wait_for_eventlog_analyzer to wait for ELA readiness."
echo "=== ManageEngine EventLog Analyzer Post-Start Done ==="
