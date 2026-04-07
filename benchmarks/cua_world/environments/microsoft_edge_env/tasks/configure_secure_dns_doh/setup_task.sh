#!/bin/bash
# setup_task.sh - Pre-task hook for configure_secure_dns_doh
# Resets Edge DNS settings to insecure defaults and launches browser.

set -e

TASK_NAME="configure_secure_dns_doh"
START_TS_FILE="/tmp/task_start_ts.txt"
PREFS_FILE="/home/ga/.config/microsoft-edge/Default/Preferences"

echo "=== Setting up ${TASK_NAME} ==="

# 1. Kill any running Edge instances to release file locks
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Record task start timestamp for anti-gaming
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# 3. Clean up previous run artifacts
rm -f "/home/ga/Desktop/doh_verification.png"
rm -f "/home/ga/Desktop/doh_status.txt"

# 4. Reset DNS settings in Preferences to ensure a clean start
# We explicitly disable DoH so the agent has to enable it.
echo "Resetting DNS settings..."
if [ -f "$PREFS_FILE" ]; then
    python3 << 'PYEOF'
import json
import os

prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
try:
    with open(prefs_path, 'r') as f:
        data = json.load(f)
    
    # Reset dns_over_https settings
    # mode: "off" (disabled) or "automatic" (default)
    # templates: clear any custom providers
    if 'dns_over_https' not in data:
        data['dns_over_https'] = {}
    
    data['dns_over_https']['mode'] = "off"
    data['dns_over_https']['templates'] = ""
    
    with open(prefs_path, 'w') as f:
        json.dump(data, f)
    print("DNS settings reset to 'off'.")
except Exception as e:
    print(f"Error resetting preferences: {e}")
PYEOF
else
    echo "Preferences file not found, Edge will start with defaults."
fi

# 5. Launch Microsoft Edge
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --password-store=basic \
    --start-maximized \
    > /tmp/edge.log 2>&1 &"

# 6. Wait for Edge window
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="