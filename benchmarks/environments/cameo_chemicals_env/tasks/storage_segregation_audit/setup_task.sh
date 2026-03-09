#!/bin/bash
# setup_task.sh - Pre-task hook for storage_segregation_audit
# Sets up a comprehensive chemical storage audit scenario using the full facility inventory

echo "=== Setting up storage_segregation_audit task ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# Kill any existing Firefox instances
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Ensure output directory exists
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Remove any pre-existing output file (anti-gaming: force fresh work)
rm -f /home/ga/Documents/storage_audit_report.txt 2>/dev/null || true

# Copy facility chemical inventory to Desktop (the agent's primary reference)
cp /workspace/data/facility_chemical_inventory.csv /home/ga/Desktop/ 2>/dev/null || true
chown ga:ga /home/ga/Desktop/facility_chemical_inventory.csv 2>/dev/null || true

# Record baseline: confirm output file does not exist at task start
if [ -f "/home/ga/Documents/storage_audit_report.txt" ]; then
    echo "ERROR: Output file already exists, could not delete it"
else
    echo "Confirmed: output file does not exist at task start (anti-gaming OK)"
fi

echo "0" > /tmp/initial_output_file_exists
echo "Baseline recorded"

# Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox to CAMEO Chemicals..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

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

echo "=== storage_segregation_audit setup complete ==="
echo "Firefox open at CAMEO Chemicals."
echo "Facility inventory at ~/Desktop/facility_chemical_inventory.csv"
echo "Agent must audit ALL 15 chemicals for dangerous co-storage combinations."
