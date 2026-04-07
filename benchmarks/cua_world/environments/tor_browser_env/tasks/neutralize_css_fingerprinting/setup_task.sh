#!/bin/bash
# setup_task.sh for neutralize_css_fingerprinting task
# Prepares the tracking payload and resets Tor Browser settings to baseline

set -e
echo "=== Setting up neutralize_css_fingerprinting task ==="

TASK_NAME="neutralize_css_fingerprinting"

# Record task start timestamp for anti-gaming
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Remove any old screenshot output to prevent 'do nothing' passing
rm -f /home/ga/Documents/safe_render.png 2>/dev/null || true

# Generate the CSS tracking honeypot payload (Real-world CSS tracking simulation)
# This simulates font enumeration and color probing.
cat > /home/ga/Documents/css_tracking_honeypot.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>CSS Fingerprinting Probe</title>
    <style>
        /* Hostile styling to test overrides */
        body { 
            background-color: #ff00ff !important; /* Magenta */
            color: #00ff00 !important; /* Lime */
            font-family: "Impact", "Comic Sans MS", cursive !important;
        }
        .probe-container {
            border: 5px dashed yellow;
            padding: 20px;
            margin: 20px;
            font-size: 24px;
        }
        .warning {
            font-weight: bold;
            font-size: 32px;
        }
        /* Simulated font enumeration elements */
        @font-face { font-family: 'TrackingFont1'; src: local('Arial'); }
        @font-face { font-family: 'TrackingFont2'; src: local('Helvetica'); }
        .font-probe { font-family: 'TrackingFont1', 'TrackingFont2', sans-serif; }
    </style>
</head>
<body>
    <div class="probe-container">
        <p class="warning">⚠️ CSS PROBE ACTIVE ⚠️</p>
        <p>If you see a <b>MAGENTA</b> background and <b>LIME GREEN</b> text, your browser is vulnerable to CSS color tracking.</p>
        <p class="font-probe">If this text appears in an overridden custom font (like Impact or Comic Sans), you are vulnerable to font enumeration.</p>
        <p><b>GOAL:</b> Configure Tor Browser settings to force default fonts and colors, overriding this page's CSS. Then take a screenshot of this neutralized page and save it to <code>/home/ga/Documents/safe_render.png</code>.</p>
    </div>
    <!-- Large blank space to simulate scroll tracking -->
    <div style="height: 2000px;"></div>
    <p>Scroll tracking probe bottom</p>
</body>
</html>
EOF
chown ga:ga /home/ga/Documents/css_tracking_honeypot.html

# Kill any existing Tor Browser instances for clean start
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

# Find Tor Browser profile and reset target preferences to baseline
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        echo "Found Tor Browser profile at: $PROFILE_DIR"
        break
    fi
done

PREFS_FILE="$PROFILE_DIR/prefs.js"
if [ -n "$PROFILE_DIR" ] && [ -f "$PREFS_FILE" ]; then
    echo "Resetting target prefs to unhardened state..."
    sed -i '/browser\.display\.use_document_fonts/d' "$PREFS_FILE" 2>/dev/null || true
    sed -i '/browser\.display\.document_color_use/d' "$PREFS_FILE" 2>/dev/null || true
    sed -i '/general\.smoothScroll/d' "$PREFS_FILE" 2>/dev/null || true
fi

# Launch Tor Browser
TOR_BROWSER_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser"
do
    if [ -d "$candidate/Browser" ]; then
        TOR_BROWSER_DIR="$candidate"
        break
    fi
done

echo "Launching Tor Browser..."
if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# Wait for window
echo "Waiting for Tor Browser window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting"; then
        echo "Tor Browser window appeared"
        break
    fi
    sleep 2
done

# Focus and maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial state screenshot
sleep 2
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== setup_task complete ==="