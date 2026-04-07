#!/bin/bash
set -e

echo "=== Setting up PubMed Central Paper Archival Task ==="

# Source utilities
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Clean up environment
echo "Cleaning up previous run artifacts..."
rm -rf "/home/ga/Documents/JournalClub"
# Also clean up Downloads to ensure we track new files accurately
rm -f /home/ga/Downloads/*.pdf

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 3. Kill existing Edge instances
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true

# 4. Launch Edge to blank page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge.log 2>&1 &"

# 5. Wait for window
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge window found."
        break
    fi
    sleep 1
done

# 6. Maximize window
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Edge" 2>/dev/null || true

# 7. Take initial screenshot
echo "Taking initial screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="