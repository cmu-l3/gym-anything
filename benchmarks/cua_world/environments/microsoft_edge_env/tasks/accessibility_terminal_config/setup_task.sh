#!/bin/bash
# Setup for Accessibility Terminal Config task
# Resets Edge to standard defaults (small fonts) to ensure the agent must actively change them.

set -e

TASK_NAME="accessibility_terminal_config"
DOC_PATH="/home/ga/Desktop/accessibility_config_guide.txt"
START_TS_FILE="/tmp/task_start_ts.txt"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill any running Edge instances to allow preference modification
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Remove stale documentation file
rm -f "${DOC_PATH}"

# 3. Record task start timestamp
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# 4. Reset Edge Preferences to "Standard/Inaccessible" defaults
# We explicitly set small fonts and wrong homepage to verify the agent changes them.
PREFS_DIR="/home/ga/.config/microsoft-edge/Default"
mkdir -p "$PREFS_DIR"
PREFS_FILE="$PREFS_DIR/Preferences"

echo "Resetting Edge Preferences..."
python3 << 'PYEOF'
import json
import os

prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
try:
    if os.path.exists(prefs_path):
        with open(prefs_path, 'r') as f:
            prefs = json.load(f)
    else:
        prefs = {}

    # Reset Accessibility/Font settings to defaults
    if "webkit" not in prefs: prefs["webkit"] = {}
    if "webprefs" not in prefs["webkit"]: prefs["webkit"]["webprefs"] = {}
    
    # Standard size (16px) and tiny minimum (0px)
    prefs["webkit"]["webprefs"]["default_font_size"] = 16
    prefs["webkit"]["webprefs"]["minimum_font_size"] = 0
    
    # Reset Homepage
    prefs["homepage"] = "about:blank"
    prefs["homepage_is_newtabpage"] = False
    
    # Hide home button
    if "browser" not in prefs: prefs["browser"] = {}
    prefs["browser"]["show_home_button"] = False
    
    # Reset startup behavior (5 = Open New Tab Page)
    if "session" not in prefs: prefs["session"] = {}
    prefs["session"]["restore_on_startup"] = 5

    with open(prefs_path, 'w') as f:
        json.dump(prefs, f)
    print("Preferences reset successfully.")
except Exception as e:
    print(f"Error resetting preferences: {e}")
PYEOF

# Fix permissions
chown -R ga:ga "/home/ga/.config/microsoft-edge"

# 5. Launch Edge so the agent starts with the browser open
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    > /tmp/edge.log 2>&1 &"

# Wait for window
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Maximize
DISPLAY=:1 wmctrl -r "Microsoft Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="