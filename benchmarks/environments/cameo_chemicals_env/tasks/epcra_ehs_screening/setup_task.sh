#!/bin/bash
echo "=== Setting up EPCRA EHS Screening Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: remove output file if it exists
rm -f /home/ga/Desktop/epcra_screening_report.csv
echo "Cleaned up previous output files."

# Launch Firefox to CAMEO Chemicals homepage
# Using the utility function from task_utils.sh if available, otherwise manual
if type launch_firefox_to_url &>/dev/null; then
    launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga"
else
    # Fallback manual launch
    echo "Launching Firefox manually..."
    pkill -u ga -f firefox 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"
    wait_for_window "Firefox" 45
    maximize_firefox
fi

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="