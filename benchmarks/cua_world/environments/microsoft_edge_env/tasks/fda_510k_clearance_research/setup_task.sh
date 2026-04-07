#!/bin/bash
# setup_task.sh - Pre-task hook for FDA 510(k) Research

set -e

echo "=== Setting up FDA 510(k) Research Task ==="

# 1. Kill any running Edge instances to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true

# 2. Prepare output directory (ensure it's clean)
OUTPUT_DIR="/home/ga/Documents/FDA_Research"
if [ -d "$OUTPUT_DIR" ]; then
    echo "Cleaning existing output directory..."
    rm -rf "$OUTPUT_DIR"
fi
# Do NOT create the directory; let the agent create it or just save files there (filesys implicit)
# Actually, better to ensure parent docs dir exists
mkdir -p "/home/ga/Documents"
chown ga:ga "/home/ga/Documents"

# 3. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Record initial history state (baseline)
# We want to detect visits to accessdata.fda.gov
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
INITIAL_FDA_VISITS="0"

if [ -f "$HISTORY_DB" ]; then
    # Create a temp copy to read without locking
    cp "$HISTORY_DB" /tmp/history_baseline.db
    chmod 666 /tmp/history_baseline.db
    
    INITIAL_FDA_VISITS=$(sqlite3 /tmp/history_baseline.db "SELECT COUNT(*) FROM urls WHERE url LIKE '%accessdata.fda.gov%';" 2>/dev/null || echo "0")
    rm -f /tmp/history_baseline.db
fi
echo "$INITIAL_FDA_VISITS" > /tmp/initial_fda_visits.txt
echo "Initial FDA visits: $INITIAL_FDA_VISITS"

# 5. Launch Microsoft Edge to a blank page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge_launch.log 2>&1 &"

# Wait for Edge to appear
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="