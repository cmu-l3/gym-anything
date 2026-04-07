#!/bin/bash
# Setup for Legislative History Research task

set -e

echo "=== Setting up Legislative History Research Task ==="

# 1. Kill any running Edge instances to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true

# 2. Prepare directories and clean up old artifacts
echo "Preparing directories..."
TARGET_DIR="/home/ga/Documents/Legislation"
mkdir -p "$TARGET_DIR"
chown ga:ga "$TARGET_DIR"

# Remove specific target files if they exist from previous runs
rm -f "$TARGET_DIR/chips_act_final.pdf"
rm -f "$TARGET_DIR/vote_tally.txt"

# 3. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Record initial browser history state (to detect new visits)
# We count visits to congress.gov
INITIAL_VISITS=$(sqlite3 /home/ga/.config/microsoft-edge/Default/History "SELECT COUNT(*) FROM urls WHERE url LIKE '%congress.gov%';" 2>/dev/null || echo "0")
echo "$INITIAL_VISITS" > /tmp/initial_congress_visits.txt

# 5. Launch Edge to a blank page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge_launch.log 2>&1 &"

# Wait for Edge window
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="