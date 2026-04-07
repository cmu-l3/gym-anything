#!/bin/bash
# Setup for SEC Filing Retrieval task

set -e

echo "=== Setting up sec_filing_retrieval task ==="

# Source utilities
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Clean up Documents directory to ensure no pre-existing files
echo "Cleaning Documents directory..."
rm -rf /home/ga/Documents/*
mkdir -p /home/ga/Documents
# Create a dummy file to ensure directory exists and isn't empty (optional, but good practice)
touch /home/ga/Documents/.keep

# 2. Kill existing Edge instances
echo "Killing Edge instances..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2

# 3. Record task start time for anti-gaming (file timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Record initial history state (to verify navigation happened during task)
# We'll just assume any visit to sec.gov after start time is valid, 
# but for robustness we could count existing visits.
# Here we just rely on the timestamp check in export.

# 5. Launch Microsoft Edge
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --password-store=basic \
    --start-maximized \
    > /tmp/edge.log 2>&1 &"

# 6. Wait for Edge to appear
echo "Waiting for Edge..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge window found."
        break
    fi
    sleep 1
done

# 7. Maximize window explicitly
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="