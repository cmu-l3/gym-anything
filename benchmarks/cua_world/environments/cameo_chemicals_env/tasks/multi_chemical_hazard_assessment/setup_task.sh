#!/bin/bash
# setup_task.sh - Pre-task hook for multi_chemical_hazard_assessment
# Opens Firefox to CAMEO Chemicals with warehouse inventory on Desktop
echo "=== Setting up multi_chemical_hazard_assessment task ==="

# Source utilities
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record start time
date +%s > /tmp/task_start_time
echo "Task start time: $(cat /tmp/task_start_time)"

# Kill any existing Firefox
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Ensure output directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Remove any pre-existing output file (anti-gaming)
rm -f /home/ga/Documents/warehouse_hazard_assessment.txt 2>/dev/null || true

# Copy warehouse inventory to Desktop
cp /workspace/data/facility_chemical_inventory.csv /home/ga/Desktop/ 2>/dev/null || true
chown ga:ga /home/ga/Desktop/facility_chemical_inventory.csv 2>/dev/null || true

# Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox to CAMEO Chemicals..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox process
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f firefox > /dev/null; then
        echo "Firefox process started after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Wait for Firefox window
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window appeared after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Let page load
sleep 5

# Maximize and focus Firefox
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    echo "Firefox window maximized: $WINDOW_ID"
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== multi_chemical_hazard_assessment task setup complete ==="
echo "Firefox is open at CAMEO Chemicals. Warehouse inventory is on Desktop."
echo "Agent should check all 3 pairwise combinations: Ammonia+NitricAcid, Ammonia+Acetone, NitricAcid+Acetone."
