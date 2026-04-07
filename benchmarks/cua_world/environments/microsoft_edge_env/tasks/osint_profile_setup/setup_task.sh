#!/bin/bash
# setup_task.sh - Setup for OSINT Profile Setup task

set -e

echo "=== Setting up OSINT Profile Setup Task ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill any running Edge instances
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 3. Clean up previous artifacts
rm -f "/home/ga/Desktop/osint_profile_config.txt"

# 4. Record Initial Profile State
# We need to know which profiles existed BEFORE the task to verify a NEW one was created.
LOCAL_STATE_FILE="/home/ga/.config/microsoft-edge/Local State"
INITIAL_PROFILES="[]"

if [ -f "$LOCAL_STATE_FILE" ]; then
    # Extract list of profile directory names (e.g., ["Default", "Profile 1"])
    INITIAL_PROFILES=$(python3 -c "import json, sys; 
try:
    data = json.load(open('$LOCAL_STATE_FILE'))
    profiles = list(data.get('profile', {}).get('info_cache', {}).keys())
    print(json.dumps(profiles))
except:
    print('[]')")
fi

echo "$INITIAL_PROFILES" > /tmp/initial_profiles.json
echo "Initial profiles recorded: $INITIAL_PROFILES"

# 5. Launch Edge (Default Profile)
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --password-store=basic \
    > /tmp/edge_launch.log 2>&1 &"

# Wait for Edge to appear
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window detected after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="