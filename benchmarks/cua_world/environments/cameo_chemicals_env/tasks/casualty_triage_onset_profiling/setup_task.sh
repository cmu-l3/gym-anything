#!/bin/bash
echo "=== Setting up Casualty Triage Onset Profiling Task ==="

# Source utilities
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/triage_classification.json
echo "Cleaned previous output files."

# Launch Firefox to CAMEO Chemicals homepage
# We use a specific profile to ensure no welcome screens
echo "Launching Firefox..."
if ! pgrep -u ga -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"
    
    # Wait for Firefox process
    wait_for_process "firefox" 30
    
    # Wait for window to appear
    wait_for_window "firefox\|mozilla\|CAMEO" 30
fi

# Maximize the window for better agent visibility
maximize_firefox 2>/dev/null || true

# Focus the window
WID=$(get_firefox_window_id)
focus_window "$WID"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="