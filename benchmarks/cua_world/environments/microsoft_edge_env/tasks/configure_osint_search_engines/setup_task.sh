#!/bin/bash
# setup_task.sh - Pre-task hook for configure_osint_search_engines
# Ensures clean state for Edge settings and history

set -e
echo "=== Setting up OSINT Configuration Task ==="

# 1. Record Task Start Time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Kill Edge to ensure DBs are unlocked and we can reset state
echo "Killing Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 3. Clean up previous run artifacts
REPORT_FILE="/home/ga/Desktop/osint_config_report.txt"
if [ -f "$REPORT_FILE" ]; then
    echo "Removing old report file..."
    rm "$REPORT_FILE"
fi

# 4. (Optional) Reset Web Data/Keywords if needed
# We assume the environment starts with a relatively clean profile. 
# Modifying SQLite directly here is risky without damaging the profile structure,
# so we rely on the specific keywords 'wayback', 'crt', 'shodan' not being present by default.

# 5. Launch Edge to a blank page
echo "Launching Microsoft Edge..."
# Using --no-first-run and other flags to ensure agent gets straight to work
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge_launch.log 2>&1 &"

# 6. Wait for Window
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "Edge|Microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# 7. Maximize Window
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="