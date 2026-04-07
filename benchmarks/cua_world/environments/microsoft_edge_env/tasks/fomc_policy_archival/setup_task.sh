#!/bin/bash
set -e
echo "=== Setting up FOMC Policy Archival Task ==="

# Source utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill existing Edge instances to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Clean up previous run artifacts
echo "Cleaning up previous artifacts..."
rm -rf /home/ga/Documents/FOMC_Policy
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 3. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 4. Launch Edge
echo "Launching Microsoft Edge..."
# Launch with specific flags to ensure stability and no first-run popups
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --disable-extensions \
    --disable-component-update \
    --disable-background-networking \
    --disable-client-side-phishing-detection \
    --disable-default-apps \
    --disable-infobars \
    --password-store=basic \
    --start-maximized \
    'about:blank' > /tmp/edge.log 2>&1 &"

# 5. Wait for Edge window
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# 6. Ensure window is maximized and focused
echo "Maximizing window..."
# Get the window ID (first one found)
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="