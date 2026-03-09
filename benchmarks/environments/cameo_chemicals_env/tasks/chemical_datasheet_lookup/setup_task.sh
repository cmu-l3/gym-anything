#!/bin/bash
# setup_task.sh - Pre-task hook for chemical_datasheet_lookup
# Opens Firefox to CAMEO Chemicals search page with assessment request on Desktop
echo "=== Setting up chemical_datasheet_lookup task ==="

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
rm -f /home/ga/Documents/benzene_properties.txt 2>/dev/null || true

# Copy assessment request to Desktop
cp /workspace/data/safety_assessment_request.txt /home/ga/Desktop/ 2>/dev/null || true
chown ga:ga /home/ga/Desktop/safety_assessment_request.txt 2>/dev/null || true

# Launch Firefox directly to CAMEO Chemicals search page
echo "Launching Firefox to CAMEO Chemicals search..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/search/simple' > /tmp/firefox.log 2>&1 &"

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

echo "=== chemical_datasheet_lookup task setup complete ==="
echo "Firefox is open at CAMEO Chemicals search page."
echo "Agent should search for Benzene and extract physical properties."
