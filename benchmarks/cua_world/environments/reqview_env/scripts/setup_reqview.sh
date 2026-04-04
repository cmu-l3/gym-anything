#!/bin/bash
set -euo pipefail

echo "=== Setting up ReqView ==="

# Wait for desktop to be ready
sleep 5

# Find ReqView binary (check /opt/ReqView first — that's where .deb installs it)
REQVIEW_BIN=""
for candidate in /opt/ReqView/reqview /usr/bin/reqview /usr/local/bin/reqview; do
    if [ -f "$candidate" ]; then
        REQVIEW_BIN="$candidate"
        break
    fi
done
if [ -z "$REQVIEW_BIN" ]; then
    REQVIEW_BIN=$(find /opt /usr -name "reqview" -type f 2>/dev/null | head -1 || true)
fi

if [ -z "$REQVIEW_BIN" ]; then
    echo "ERROR: ReqView binary not found"
    exit 1
fi
echo "ReqView binary: $REQVIEW_BIN"

# Create required directories
mkdir -p /home/ga/.config/ReqView
mkdir -p /home/ga/Documents/ReqView/ExampleProject
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Documents/ReqView
chown -R ga:ga /home/ga/.config/ReqView

# Copy the bundled example project data (from our mounted workspace)
# This is done before the warm-up so it's available immediately after setup
if [ -d /workspace/data/ExampleProject ]; then
    echo "Copying example project from workspace data..."
    cp -r /workspace/data/ExampleProject/. /home/ga/Documents/ReqView/ExampleProject/
    chown -R ga:ga /home/ga/Documents/ReqView/ExampleProject
    echo "Example project copied successfully"
else
    echo "WARNING: No data directory mounted at /workspace/data"
fi

# Create desktop shortcut
cat > /home/ga/Desktop/ReqView.desktop << EOF
[Desktop Entry]
Name=ReqView
Comment=Requirements Management Tool
Exec=${REQVIEW_BIN}
Icon=reqview
Type=Application
Categories=Development;
Terminal=false
StartupWMClass=ReqView
EOF
chown ga:ga /home/ga/Desktop/ReqView.desktop
chmod +x /home/ga/Desktop/ReqView.desktop

# --- Warm-up launch to initialize ReqView config and accept first-run dialogs ---
# Goal: accept EULA + fill contact details so they are persisted in ~/.config/ReqView/
# These are stored in IndexedDB and persist for all subsequent runs of ReqView.
echo "Performing warm-up launch of ReqView..."

export XAUTHORITY=/home/ga/.Xauthority
export DISPLAY=:1

# Launch ReqView (no project — shows first-run dialogs)
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid '${REQVIEW_BIN}' > /tmp/reqview_warmup.log 2>&1 &"

# Poll for ReqView window (Electron takes 15-30 seconds to start)
REQVIEW_READY=false
for i in $(seq 1 20); do
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "reqview"; then
        REQVIEW_READY=true
        echo "ReqView window detected after $((i * 3))s"
        break
    fi
    sleep 3
done

if [ "$REQVIEW_READY" = false ]; then
    echo "WARNING: ReqView window did not appear during warm-up"
    pkill -f "reqview" 2>/dev/null || true
    echo "=== ReqView setup complete (warm-up skipped — EULA may appear on first agent run) ==="
    exit 0
fi

sleep 3  # Extra time for EULA dialog to fully render

# ----- CRITICAL: Maximize window BEFORE clicking dialogs -----
# Dialog coordinates (1266, 840) etc. assume a MAXIMIZED 1920x1080 window.
# Without this, the click misses the Accept button and EULA persists on every launch.
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "ReqView" 2>/dev/null || true
sleep 0.5
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "ReqView" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take diagnostic screenshot before EULA click
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/reqview_warmup_before_eula.png 2>/dev/null || true

# ----- Step 1: Accept EULA -----
# Scroll EULA text area first (the dialog appears at center of maximized screen)
for i in 1 2 3 4 5; do
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 960 500 scroll --clearmodifiers down 5 2>/dev/null || true
    sleep 0.2
done
sleep 1

# EULA Accept button: ~(1266, 840) in 1920x1080 maximized window
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1266 840 click 1 2>/dev/null || true
sleep 4

# Take diagnostic screenshot after EULA
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/reqview_warmup_after_eula.png 2>/dev/null || true

# ----- Step 2: Fill contact details and click Agree -----
# After EULA dismiss, the "Set Up Your Contact Details" dialog appears.
# In a maximized 1920x1080 window, Name field is at approximately (765, 498).
# We click it, clear it, type, then Tab to email, Tab to Company, Tab to Agree, Return.

# Click on Name field
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 765 498 click 1 2>/dev/null || true
sleep 0.3
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+a 2>/dev/null || true
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers "GA User" 2>/dev/null || true
sleep 0.3

# Tab to Email field
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Tab 2>/dev/null || true
sleep 0.3
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+a 2>/dev/null || true
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers "ga@example.com" 2>/dev/null || true
sleep 0.3

# Tab to Company field (leave blank)
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Tab 2>/dev/null || true
sleep 0.2
# Tab past "I agree to the Privacy Policy" link (it is a tab-stop before Agree button)
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Tab 2>/dev/null || true
sleep 0.2
# Tab to Agree button
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Tab 2>/dev/null || true
sleep 0.2
# Press Enter to submit Agree
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return 2>/dev/null || true
sleep 3

# Take diagnostic screenshot after contact
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/reqview_warmup_after_contact.png 2>/dev/null || true

# ----- Step 3: Close ReqView -----
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -c "ReqView" 2>/dev/null || true
sleep 3
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Verify EULA acceptance by checking ReqView log
if grep -q "Hide dialog 'eulaDialog'" /home/ga/.config/ReqView/logs/ReqView.log 2>/dev/null; then
    echo "EULA acceptance confirmed in ReqView log"
else
    echo "WARNING: Could not confirm EULA acceptance from log — agents may see EULA dialog"
fi

echo "ReqView config directory:"
ls -la /home/ga/.config/ReqView/ 2>/dev/null | head -10 || echo "  (empty)"

echo "Example project files:"
ls /home/ga/Documents/ReqView/ExampleProject/ 2>/dev/null || echo "  (empty)"

echo "=== ReqView setup complete ==="
