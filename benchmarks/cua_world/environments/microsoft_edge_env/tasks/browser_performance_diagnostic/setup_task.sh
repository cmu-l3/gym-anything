#!/bin/bash
# setup_task.sh - Setup for Browser Performance Diagnostic task
# Ensures Edge is closed, resets specific performance settings to 'false',
# and records the start timestamp.

set -e

TASK_NAME="browser_performance_diagnostic"
REPORT_FILE="/home/ga/Desktop/performance_report.txt"
START_TS_FILE="/tmp/task_start_time.txt"
PREFS_FILE="/home/ga/.config/microsoft-edge/Default/Preferences"

echo "=== Setting up ${TASK_NAME} ==="

# 1. Kill any running Edge instances
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Remove any stale report file
if [ -f "${REPORT_FILE}" ]; then
    echo "Removing stale report file..."
    rm -f "${REPORT_FILE}"
fi

# 3. Ensure Preferences file exists and disable target settings (Sleeping Tabs/Startup Boost)
# This forces the agent to actually change them.
mkdir -p "$(dirname "$PREFS_FILE")"

# We use Python to safely modify the JSON preferences
python3 << 'PYEOF'
import json
import os

prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"

# Default empty structure if file doesn't exist
data = {}
if os.path.exists(prefs_path):
    try:
        with open(prefs_path, 'r') as f:
            data = json.load(f)
    except:
        data = {}

# Ensure 'browser' dictionary exists
if 'browser' not in data:
    data['browser'] = {}

# DISABLE Sleeping Tabs (so agent must enable it)
# Note: Key locations can vary by version, setting common ones
data['browser']['sleeping_tabs'] = {"enabled": False}

# DISABLE Startup Boost
data['browser']['startup_boost'] = {"enabled": False}

# Write back
with open(prefs_path, 'w') as f:
    json.dump(data, f, indent=2)

print("Performance settings reset to DISABLED.")
PYEOF

# 4. Record task start timestamp (for history verification)
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# 5. Launch Edge to a blank page to start
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --password-store=basic \
    about:blank > /tmp/edge_launch.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="