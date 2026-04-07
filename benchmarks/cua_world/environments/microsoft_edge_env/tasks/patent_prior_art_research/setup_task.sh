#!/bin/bash
set -e
echo "=== Setting up Patent Prior Art Research Task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up any previous run artifacts
# We want the agent to demonstrate directory creation and downloading
rm -rf /home/ga/Documents/Patents
rm -f /home/ga/Downloads/US5255452.pdf
rm -f /home/ga/Downloads/patent_summary.txt

# 3. Ensure Microsoft Edge is running and clean
# Kill existing instances to start fresh
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2

# Launch Edge to a neutral page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    'about:blank' > /dev/null 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Edge" 2>/dev/null || true

# 4. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="