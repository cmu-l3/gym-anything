#!/bin/bash
set -e
echo "=== Setting up Firefox Accessibility Override Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is completely killed
pkill -f firefox 2>/dev/null || true
sleep 2
pkill -9 -f firefox 2>/dev/null || true

# Clean up any potential previous overrides from the default profile
PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
if [ -f "$PROFILE_DIR/prefs.js" ]; then
    echo "Cleaning existing accessibility prefs to ensure clean state..."
    sed -i '/browser.display.document_color_use/d' "$PROFILE_DIR/prefs.js"
    sed -i '/browser.display.use_document_fonts/d' "$PROFILE_DIR/prefs.js"
    sed -i '/browser.display.background_color/d' "$PROFILE_DIR/prefs.js"
    sed -i '/browser.display.foreground_color/d' "$PROFILE_DIR/prefs.js"
    sed -i '/font.name./d' "$PROFILE_DIR/prefs.js"
    sed -i '/font.size./d' "$PROFILE_DIR/prefs.js"
fi

# Launch Firefox
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox about:blank &"
sleep 5

# Maximize the window for visibility
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="