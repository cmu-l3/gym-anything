#!/bin/bash
# setup_task.sh - Pre-task hook for osm_geolocation_verification
# Ensures Edge is clean and records start time.

set -e
echo "=== Setting up OSM Geolocation Verification Task ==="

# 1. Kill any existing Edge instances to start fresh
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Clean up previous report if it exists
REPORT_FILE="/home/ga/Desktop/geo_verification_report.txt"
if [ -f "$REPORT_FILE" ]; then
    echo "Removing previous report file..."
    rm "$REPORT_FILE"
fi

# 3. Reset Edge Permissions (Optional but good for reproducibility)
# We want the agent to handle the permission prompt, so we ensure it's not already allowed.
PREFS_FILE="/home/ga/.config/microsoft-edge/Default/Preferences"
if [ -f "$PREFS_FILE" ]; then
    echo "Resetting geolocation permissions in Preferences..."
    # Use python to safely remove the geolocation exception for openstreetmap
    python3 << 'PYEOF'
import json
import os

prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
try:
    with open(prefs_path, 'r') as f:
        data = json.load(f)
    
    # Navigate to content_settings.exceptions.geolocation
    if 'profile' in data and 'content_settings' in data['profile'] and 'exceptions' in data['profile']['content_settings']:
        geo_exceptions = data['profile']['content_settings']['exceptions'].get('geolocation', {})
        keys_to_remove = [k for k in geo_exceptions.keys() if 'openstreetmap.org' in k]
        
        if keys_to_remove:
            print(f"Removing pre-existing permissions for: {keys_to_remove}")
            for k in keys_to_remove:
                del geo_exceptions[k]
            
            with open(prefs_path, 'w') as f:
                json.dump(data, f)
except Exception as e:
    print(f"Error resetting prefs: {e}")
PYEOF
fi

# 4. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 5. Launch Edge to a blank page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge_launch.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="