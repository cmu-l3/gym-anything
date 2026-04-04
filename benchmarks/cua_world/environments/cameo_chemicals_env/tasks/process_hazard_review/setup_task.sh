#!/bin/bash
# setup_task.sh - Pre-task hook for process_hazard_review
# Sets up a methyl acrylate synthesis PHA scenario

echo "=== Setting up process_hazard_review task ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record start timestamp
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# Kill any existing Firefox instances
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Remove any pre-existing output file (anti-gaming)
rm -f /home/ga/Documents/process_hazard_report.txt 2>/dev/null || true

# Copy synthesis process description to Desktop
cp /workspace/data/synthesis_process_description.txt /home/ga/Desktop/ 2>/dev/null || true
chown ga:ga /home/ga/Desktop/synthesis_process_description.txt 2>/dev/null || true

# Record baseline: confirm output file does not exist
if [ -f "/home/ga/Documents/process_hazard_report.txt" ]; then
    echo "ERROR: Output file already exists, could not delete it"
else
    echo "Confirmed: output file does not exist at task start (anti-gaming OK)"
fi

echo "0" > /tmp/initial_output_file_exists
echo "Baseline recorded"

# Launch Firefox to CAMEO Chemicals Reactivity tool
echo "Launching Firefox to CAMEO Chemicals Reactivity tool..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/react/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox process to start
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

echo "=== process_hazard_review setup complete ==="
echo "Firefox open at CAMEO Chemicals Reactivity tool."
echo "Process description at ~/Desktop/synthesis_process_description.txt"
echo "Agent must check all chemical pairs for reactive hazards and identify safety gaps."
