#!/bin/bash
# setup_task.sh - Pre-task hook for configure_edge_flags
# Cleans up Edge state and ensures a fresh start

set -e

echo "=== Setting up configure_edge_flags task ==="

# 1. Kill any running Edge instances to release file locks
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Record Task Start Time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 3. Clean up previous artifacts
rm -f "/home/ga/Desktop/edge_flags_config.txt"

# 4. Reset Local State (flags) to default
# The 'enabled_labs_experiments' list in 'Local State' controls active flags.
# We remove this list to reset all flags to Default.
LOCAL_STATE_FILE="/home/ga/.config/microsoft-edge/Local State"

if [ -f "$LOCAL_STATE_FILE" ]; then
    echo "Resetting experimental flags in Local State..."
    # Use python to safely modify JSON
    python3 -c "
import json
import os

path = '$LOCAL_STATE_FILE'
try:
    with open(path, 'r') as f:
        data = json.load(f)
    
    # Remove experiments list if it exists
    if 'browser' in data and 'enabled_labs_experiments' in data['browser']:
        del data['browser']['enabled_labs_experiments']
        print('Cleared enabled_labs_experiments')
    
    with open(path, 'w') as f:
        json.dump(data, f)
except Exception as e:
    print(f'Error resetting flags: {e}')
"
fi

# 5. Launch Edge
echo "Launching Microsoft Edge..."
# We launch with minimal flags to ensure the UI is standard
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --password-store=basic \
    about:blank > /tmp/edge_launch.log 2>&1 &"

# 6. Wait for Edge window
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# 7. Maximize window
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="