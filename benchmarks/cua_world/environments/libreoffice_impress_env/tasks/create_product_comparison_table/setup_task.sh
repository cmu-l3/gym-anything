#!/bin/bash
set -euo pipefail

echo "=== Setting up Product Comparison Table Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous attempts
rm -f "/home/ga/Documents/Presentations/comparison.odp"
mkdir -p "/home/ga/Documents/Presentations"
chown -R ga:ga "/home/ga/Documents/Presentations"

# Ensure LibreOffice Impress is running
if ! pgrep -f "soffice.bin" > /dev/null; then
    echo "Starting LibreOffice Impress..."
    su - ga -c "DISPLAY=:1 libreoffice --impress &"
    
    # Wait for window
    wait_for_window "LibreOffice Impress" 30
else
    echo "LibreOffice is already running."
fi

# Focus and maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Focusing window ID: $wid"
    focus_window "$wid"
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
else
    echo "Warning: Could not find Impress window to focus."
fi

# Dismiss "Select a Template" dialog if it appears (common on startup)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="