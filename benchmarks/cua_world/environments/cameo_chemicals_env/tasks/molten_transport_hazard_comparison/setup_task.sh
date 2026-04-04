#!/bin/bash
echo "=== Setting up Molten Transport Hazard Comparison Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure clean state: Remove output file if it exists
rm -f /home/ga/Desktop/molten_hazards.csv 2>/dev/null || true

# Ensure Firefox is running and valid
kill_firefox "ga"
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga" 45

# Verify window is ready
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    echo "Firefox window found: $WID"
    maximize_firefox
else
    echo "WARNING: Firefox window not found during setup"
fi

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="