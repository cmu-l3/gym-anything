#!/bin/bash
# setup_task.sh - Pre-task hook for save_reference_pdfs task

set -e
echo "=== Setting up save_reference_pdfs task ==="

# 1. Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous run artifacts
# Ensure target directory is gone so agent must create it
TARGET_DIR="/home/ga/Documents/Workshop_Materials"
if [ -d "$TARGET_DIR" ]; then
    echo "Removing existing target directory..."
    rm -rf "$TARGET_DIR"
fi

# Ensure parent Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Downloads

# 3. Prepare Browser State
# Kill running Edge instances to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# Clear history to ensure we can verify *new* visits
# (Optional but helpful for robust verification)
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
if [ -f "$HISTORY_DB" ]; then
    echo "Clearing relevant history entries..."
    sqlite3 "$HISTORY_DB" "DELETE FROM urls WHERE url LIKE '%wikipedia.org%';" 2>/dev/null || true
fi

# 4. Launch Edge
echo "Launching Microsoft Edge..."
# Launch with specific flags to ensure stability and no welcome screens
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --disable-extensions \
    --disable-infobars \
    --password-store=basic \
    'about:blank' > /tmp/edge_launch.log 2>&1 &"

# 5. Wait for window and maximize
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window detected"
        break
    fi
    sleep 1
done
sleep 2

# Maximize the window (CRITICAL for visual agent performance)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 6. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="