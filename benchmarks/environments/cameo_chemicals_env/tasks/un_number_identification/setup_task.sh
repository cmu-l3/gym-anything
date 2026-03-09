#!/bin/bash
set -e
echo "=== Setting up UN Number Identification Task ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback definitions
    take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/Documents/un1092_field_report.txt
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill any existing Firefox instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox process
for i in {1..45}; do
    if pgrep -u ga -f firefox > /dev/null; then
        echo "Firefox process started"
        break
    fi
    sleep 1
done

# Wait for window to appear
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Let page load fully
sleep 5

# Maximize and focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== UN Number Identification Task Setup Complete ==="