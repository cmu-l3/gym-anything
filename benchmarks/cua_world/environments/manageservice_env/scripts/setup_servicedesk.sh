#!/bin/bash
# ManageEngine ServiceDesk Plus Setup Script (post_start hook)
#
# Runs after desktop starts. Configures Firefox profile only.
# Returns quickly (<60s). Does NOT wait for SDP install (too slow).
#
# The pre_task hook in each task (setup_task.sh) calls ensure_sdp_running
# from task_utils.sh, which waits for install and starts SDP (up to 3600s).
#
# SDP Credentials: administrator / administrator
# SDP Web UI: https://localhost:8080/ManageEngine/Login.do

echo "=== ManageEngine ServiceDesk Plus Post-Start ==="

# =====================================================
# Configure Firefox snap profile
# =====================================================
echo "Configuring Firefox snap profile..."

# Fix snap Firefox data directory permissions (snap requires version-specific dir)
SNAP_FF_VERSION=$(snap list firefox 2>/dev/null | awk '/firefox/{print $3}')
if [ -n "$SNAP_FF_VERSION" ]; then
    mkdir -p "/home/ga/snap/firefox/$SNAP_FF_VERSION"
    chown -R ga:ga /home/ga/snap/firefox 2>/dev/null || true
fi

FIREFOX_PROFILE_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
mkdir -p "$FIREFOX_PROFILE_BASE/sdp.profile"

cat > "$FIREFOX_PROFILE_BASE/profiles.ini" << 'FFPROFILE'
[Install4F96D1932A9F858E]
Default=sdp.profile
Locked=1

[Profile0]
Name=sdp-profile
IsRelative=1
Path=sdp.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE

cat > "$FIREFOX_PROFILE_BASE/sdp.profile/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.homepage", "https://localhost:8080/ManageEngine/Login.do");
user_pref("browser.startup.page", 1);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("security.insecure_field_warning.contextual.enabled", false);
user_pref("security.certerrors.permanentOverride", true);
user_pref("security.default_personal_cert", "Ask Every Time");
USERJS

# Pre-add certificate exception for localhost:8080 (self-signed cert)
# This prevents the "Warning: Potential Security Risk Ahead" dialog
mkdir -p "$FIREFOX_PROFILE_BASE/sdp.profile"
python3 -c "
import json, os, time
# Create a permissions.sqlite entry is complex; instead use cert_override.txt
override_file = '$FIREFOX_PROFILE_BASE/sdp.profile/cert_override.txt'
# Write cert override for localhost:8080 (accept any self-signed cert)
with open(override_file, 'w') as f:
    f.write('# PSM Certificate Override Settings file\n')
    f.write('# This is a generated file!  Do not edit.\n')
" 2>/dev/null || true

chown -R ga:ga "$FIREFOX_PROFILE_BASE"
echo "Firefox profile configured."

# =====================================================
# Desktop shortcut
# =====================================================
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/ServiceDeskPlus.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=ManageEngine ServiceDesk Plus
Comment=ITSM Helpdesk Software
Exec=firefox https://localhost:8080/ManageEngine/Login.do
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Network;Office;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/ServiceDeskPlus.desktop
chmod +x /home/ga/Desktop/ServiceDeskPlus.desktop

# Mark desktop file as trusted so GNOME doesn't show "Untrusted Desktop File" dialog
su - ga -c "dbus-launch gio set /home/ga/Desktop/ServiceDeskPlus.desktop metadata::trusted true" 2>/dev/null || true

# =====================================================
# Background service start + Firefox launch
# =====================================================
cat > /tmp/sdp_bg_setup.sh << 'BGEOF'
#!/bin/bash
SDP_HOME="/opt/ManageEngine/ServiceDesk"
INSTALL_MARKER="/tmp/sdp_install_complete.marker"
LOG="/tmp/sdp_bg_setup.log"
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }

log "Background SDP setup started"

# Wait for install to complete (up to 50 minutes)
WAITED=0
while [ ! -f "$INSTALL_MARKER" ]; do
    sleep 15
    WAITED=$((WAITED + 15))
    if [ $WAITED -ge 3000 ]; then
        log "ERROR: Install timed out"
        exit 1
    fi
    [ $((WAITED % 120)) -eq 0 ] && log "Waiting for install... ${WAITED}s"
done

CONTENT=$(cat "$INSTALL_MARKER" 2>/dev/null)
if [ "$CONTENT" != "OK" ]; then
    log "ERROR: Install failed: $CONTENT"
    exit 1
fi
log "Install complete"

if [ ! -d "$SDP_HOME/bin" ]; then
    log "ERROR: $SDP_HOME/bin not found"
    exit 1
fi

# Fix PostgreSQL permissions
if [ -d "$SDP_HOME/pgsql" ]; then
    chmod 755 "$SDP_HOME" "$SDP_HOME/pgsql" "$SDP_HOME/pgsql/bin" "$SDP_HOME/pgsql/lib" "$SDP_HOME/pgsql/share" 2>/dev/null || true
    chmod -R a+rX "$SDP_HOME/pgsql/bin/" "$SDP_HOME/pgsql/lib/" "$SDP_HOME/pgsql/share/" 2>/dev/null || true
    [ -d "$SDP_HOME/pgsql/data" ] && chown -R postgres:postgres "$SDP_HOME/pgsql/data" 2>/dev/null && chmod 700 "$SDP_HOME/pgsql/data" 2>/dev/null || true
    id postgres &>/dev/null || useradd -r -s /bin/bash -d /var/lib/postgresql postgres 2>/dev/null || true
    mkdir -p /var/lib/postgresql
    usermod -d /var/lib/postgresql postgres 2>/dev/null || true
    chown postgres:postgres /var/lib/postgresql 2>/dev/null || true
fi

# Start SDP
pkill -f "WrapperJVMMain" 2>/dev/null || true
pkill -f "wrapper.java" 2>/dev/null || true
sleep 3

RUN_SCRIPT=""
for s in run.sh startServiceDesk.sh wrapper; do
    [ -f "$SDP_HOME/bin/$s" ] && RUN_SCRIPT="$s" && break
done

if [ -n "$RUN_SCRIPT" ]; then
    log "Starting SDP via $RUN_SCRIPT..."
    (cd "$SDP_HOME/bin" && nohup bash "$RUN_SCRIPT" > /tmp/sdp_start.log 2>&1 &)
else
    log "ERROR: No start script found"
    exit 1
fi

# Wait for web UI
log "Waiting for SDP HTTPS on port 8080..."
WAITED=0
READY=false
while [ $WAITED -lt 600 ]; do
    HTTP=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://localhost:8080/ManageEngine/Login.do" 2>/dev/null || echo "000")
    if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ] || [ "$HTTP" = "301" ]; then
        log "SDP is up! (HTTP $HTTP after ${WAITED}s)"
        READY=true
        break
    fi
    sleep 10
    WAITED=$((WAITED + 10))
    [ $((WAITED % 60)) -eq 0 ] && log "Still waiting... ${WAITED}s (HTTP: $HTTP)"
done

if [ "$READY" != "true" ]; then
    log "WARNING: SDP not responding after 600s"
fi

# Launch Firefox
log "Launching Firefox..."
PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox/sdp.profile"
mkdir -p "$PROFILE_DIR"
rm -f "$PROFILE_DIR/.parentlock" "$PROFILE_DIR/lock" 2>/dev/null || true
chown -R ga:ga /home/ga/snap/ 2>/dev/null || true

# Pre-accept self-signed cert using certutil (avoids Firefox security warning)
if command -v certutil >/dev/null 2>&1; then
    [ ! -f "$PROFILE_DIR/cert9.db" ] && certutil -N -d "sql:$PROFILE_DIR" --empty-password 2>/dev/null || true
    openssl s_client -connect "localhost:8080" -servername localhost \
        </dev/null 2>/dev/null | openssl x509 -outform PEM > /tmp/sdp_cert.pem 2>/dev/null || true
    [ -s /tmp/sdp_cert.pem ] && certutil -A -d "sql:$PROFILE_DIR" -n "ServiceDeskPlus" \
        -t "CT,," -i /tmp/sdp_cert.pem 2>/dev/null || true
    log "Self-signed cert pre-imported via certutil"
fi

pkill -9 -f firefox 2>/dev/null || true
sleep 2

su - ga -c "
    rm -f '$PROFILE_DIR/.parentlock' '$PROFILE_DIR/lock' 2>/dev/null || true
    export DISPLAY=:1
    export XAUTHORITY=/run/user/1000/gdm/Xauthority
    setsid firefox --new-instance \
        -profile '$PROFILE_DIR' \
        'https://localhost:8080/ManageEngine/Login.do' > /tmp/firefox_sdp.log 2>&1 &
"
sleep 10

# Auto-accept self-signed cert warning if it appears
CERT_WARN=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "Warning.*Security\|Potential.*Risk" | head -1)
if [ -n "$CERT_WARN" ]; then
    log "Self-signed cert warning detected, auto-accepting..."
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Tab Tab Tab Tab Return" 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Tab Tab Return" 2>/dev/null || true
    sleep 5
    log "Cert warning accepted"
fi

# Maximize Firefox
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

log "Background SDP setup complete"
echo "OK" > /tmp/sdp_service_ready.marker
BGEOF

chmod +x /tmp/sdp_bg_setup.sh
echo "Starting background SDP service setup..."
nohup bash /tmp/sdp_bg_setup.sh > /tmp/sdp_bg_nohup.log 2>&1 &
echo "Background setup PID: $!"

echo "=== Post-Start Done ==="
echo "Note: Background process will start SDP and launch Firefox when ready."
