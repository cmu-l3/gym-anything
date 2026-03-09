#!/bin/bash
set -e

echo "=== Setting up Wondershare EdrawMax ==="

# Wait for desktop to be ready
sleep 5

# Create user config and working directories
# EdrawMax uses ~/Edraw/edrawmax/ (NOT ~/.edraw/edrawmax/)
mkdir -p /home/ga/Edraw/edrawmax/localData
mkdir -p /home/ga/Edraw/edrawmax/Cache
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams

# Discover EdrawMax binary location
EDRAWMAX_BIN=""
for candidate in "/usr/bin/edrawmax" "/usr/local/bin/edrawmax"; do
    if [ -x "$candidate" ]; then
        EDRAWMAX_BIN="$candidate"
        break
    fi
done
if [ -z "$EDRAWMAX_BIN" ]; then
    EDRAWMAX_BIN=$(find /opt -name "EdrawMax" -executable -type f 2>/dev/null | head -1)
fi
if [ -z "$EDRAWMAX_BIN" ]; then
    echo "ERROR: Cannot find EdrawMax binary"
    exit 1
fi
echo "EdrawMax binary: $EDRAWMAX_BIN"

# Pre-create config files to try to suppress first-run/sign-in dialogs
# EdrawMax uses ~/Edraw/edrawmax/localData/ for user state
cat > /home/ga/Edraw/edrawmax/localData/app_config.json << 'EOCFG'
{
  "isFirstRun": false,
  "skipWelcomeScreen": true,
  "hasShownActivationDialog": true,
  "hasCompletedOnboarding": true,
  "trialMode": true,
  "autoUpdate": false,
  "checkUpdateOnStartup": false,
  "showSignInOnStartup": false
}
EOCFG

cat > /home/ga/Edraw/edrawmax/localData/user_info.json << 'EOUSR'
{
  "loginStatus": "trial",
  "isLoggedIn": false,
  "hasSkippedLogin": true,
  "trialStarted": true
}
EOUSR

cat > /home/ga/Edraw/edrawmax/preferences.json << 'EOPREF'
{
  "firstRun": false,
  "showWelcome": false,
  "autoUpdate": false,
  "checkUpdate": false,
  "showSignInDialog": false,
  "privacyPolicyAgreed": true
}
EOPREF

# Set ownership
chown -R ga:ga /home/ga/Edraw

# Create desktop shortcut for EdrawMax
cat > /home/ga/Desktop/EdrawMax.desktop << EOF
[Desktop Entry]
Name=Wondershare EdrawMax
Comment=Professional diagramming software
Exec=${EDRAWMAX_BIN}
Icon=edrawmax
Type=Application
Categories=Graphics;Office;
Terminal=false
StartupNotify=true
EOF
chmod +x /home/ga/Desktop/EdrawMax.desktop
chown ga:ga /home/ga/Desktop/EdrawMax.desktop

# === Warm-up launch to dismiss first-run / sign-in dialog ===
# This is critical: EdrawMax shows a sign-in dialog on every launch when not logged in.
# The warm-up clears any File Recovery state by launching and exiting cleanly.
echo "Starting EdrawMax warm-up launch to dismiss first-run dialogs..."

# Launch EdrawMax as ga user
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority ${EDRAWMAX_BIN}" &

# Wait for EdrawMax process to start
echo "Waiting for EdrawMax process to start..."
WAIT=0
while [ $WAIT -lt 90 ]; do
    if pgrep -f "EdrawMax" > /dev/null 2>&1; then
        echo "EdrawMax process detected after ${WAIT}s"
        break
    fi
    sleep 1
    WAIT=$((WAIT + 1))
done

if [ $WAIT -ge 90 ]; then
    echo "WARNING: EdrawMax process did not start within 90s"
fi

# Wait for EdrawMax UI to render (large Qt5/Chromium embedded app takes time)
echo "Waiting for EdrawMax UI to load..."
sleep 30

# Take a screenshot to see what's on screen
DISPLAY=:1 import -window root /home/ga/edrawmax_warmup_before.png 2>/dev/null || true
echo "Screenshot saved: /home/ga/edrawmax_warmup_before.png"

# Dismiss Account Login dialog
# The X button is at VG(863,197) = actual(1294,296) on 1920x1080
echo "Dismissing Account Login dialog..."
DISPLAY=:1 xdotool mousemove 1294 296 click 1 2>/dev/null || true
sleep 2

# Dismiss File Recovery dialog (if present)
# X button at VG(863,218) = actual(1294,327) on 1920x1080
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "File Recovery"; then
    echo "Dismissing File Recovery dialog..."
    DISPLAY=:1 xdotool mousemove 1294 327 click 1 2>/dev/null || true
    sleep 2
fi

# Press Escape as fallback for any remaining dialog
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Wait for app to settle
sleep 3

# Take another screenshot to verify state
DISPLAY=:1 import -window root /home/ga/edrawmax_warmup_after.png 2>/dev/null || true
echo "Screenshot saved: /home/ga/edrawmax_warmup_after.png"

# Close EdrawMax gracefully using Alt+F4 (avoids File Recovery dialog on next launch)
echo "Closing EdrawMax gracefully..."
DISPLAY=:1 wmctrl -c "Wondershare EdrawMax" 2>/dev/null || true
sleep 5
# If still running, use SIGTERM (not SIGKILL) to allow clean shutdown
pkill -TERM -f "EdrawMax" 2>/dev/null || true
sleep 5
# Final force kill if needed
pkill -9 -f "EdrawMax" 2>/dev/null || true
sleep 2

# Fix ownership of any config files written during warm-up
chown -R ga:ga /home/ga/Edraw 2>/dev/null || true
chown -R ga:ga /home/ga/.edraw 2>/dev/null || true

# Copy real EdrawMax template files for task use
# Templates are at /opt/apps/edrawmax/config/aiexample/ (confirmed from installation)
echo "Copying EdrawMax template files to ~/Diagrams/..."
AIEXAMPLE_DIR="/opt/apps/edrawmax/config/aiexample"
if [ -d "$AIEXAMPLE_DIR" ]; then
    find "$AIEXAMPLE_DIR" -name "*.eddx" -type f 2>/dev/null | while read -r tmpl; do
        cp "$tmpl" /home/ga/Diagrams/ 2>/dev/null || true
    done
    chown -R ga:ga /home/ga/Diagrams 2>/dev/null || true
    echo "Templates copied:"
    ls -la /home/ga/Diagrams/ 2>/dev/null || true
else
    # Fallback: search all of /opt
    echo "AIEXAMPLE_DIR not found, searching /opt for templates..."
    find /opt -name "*.eddx" -type f 2>/dev/null | head -10 | while read -r tmpl; do
        cp "$tmpl" /home/ga/Diagrams/ 2>/dev/null || true
    done
    chown -R ga:ga /home/ga/Diagrams 2>/dev/null || true
    ls -la /home/ga/Diagrams/ 2>/dev/null || true
fi

echo "=== EdrawMax setup complete ==="
