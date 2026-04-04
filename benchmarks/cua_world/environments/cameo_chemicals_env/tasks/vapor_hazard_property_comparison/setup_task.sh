#!/bin/bash
# setup_task.sh - Pre-task hook for vapor_hazard_property_comparison

set -e
echo "=== Setting up Vapor Hazard Property Comparison Task ==="

# Source shared utilities
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Prepare output directory and clean previous state
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/vapor_hazard_report.txt
echo "Cleaned previous output file."

# 3. Ensure Firefox is running and at CAMEO Chemicals homepage
# Using the shared utility if available, or manual fallback
URL="https://cameochemicals.noaa.gov/"

echo "Launching Firefox to $URL..."
if type launch_firefox_to_url &>/dev/null; then
    launch_firefox_to_url "$URL" "ga"
else
    # Fallback implementation
    pkill -u ga -f firefox 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 firefox -P default --no-remote '$URL' > /tmp/firefox.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
            echo "Firefox window appeared."
            break
        fi
        sleep 1
    done
    sleep 5
    
    # Maximize
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    fi
fi

# 4. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="