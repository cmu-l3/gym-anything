#!/bin/bash
# setup_task.sh - Pre-task hook for flood_cascade_hazard_assessment
# Sets up a multi-facility flood corridor cascading chemical hazard scenario

echo "=== Setting up flood_cascade_hazard_assessment task ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Kill any existing Firefox instances
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Ensure output directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Remove any pre-existing output file BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/flood_cascade_assessment.txt 2>/dev/null || true

# Record start timestamp (after deletion, so any file found later was created during the task)
date +%s > /tmp/task_start_time

# Record baseline: confirm output file does not exist
if [ -f "/home/ga/Documents/flood_cascade_assessment.txt" ]; then
    echo "1" > /tmp/initial_output_file_exists
    echo "WARNING: Output file still exists after deletion attempt"
else
    echo "0" > /tmp/initial_output_file_exists
    echo "Confirmed: output file does not exist at task start (anti-gaming OK)"
fi

# Copy the scenario briefing to Desktop
cp /workspace/data/flood_hazard_scenario.txt /home/ga/Desktop/ 2>/dev/null || true
chown ga:ga /home/ga/Desktop/flood_hazard_scenario.txt 2>/dev/null || true

# Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox to CAMEO Chemicals..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox process to start (up to 60 seconds)
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f firefox > /dev/null 2>&1; then
        echo "Firefox process started after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Wait for Firefox window to appear
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO|noaa"; then
        echo "Firefox window appeared after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Let the page load
sleep 5

# Maximize Firefox window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO|noaa" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    echo "Firefox window maximized: $WINDOW_ID"
fi

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== flood_cascade_hazard_assessment setup complete ==="
echo "Firefox open at CAMEO Chemicals."
echo "Scenario briefing at ~/Desktop/flood_hazard_scenario.txt"
echo "Agent must assess cascading hazards across three facilities and save to ~/Documents/flood_cascade_assessment.txt"
