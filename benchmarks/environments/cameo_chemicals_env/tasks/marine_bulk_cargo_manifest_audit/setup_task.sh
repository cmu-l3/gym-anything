#!/bin/bash
# setup_task.sh for marine_bulk_cargo_manifest_audit

echo "=== Setting up Marine Bulk Cargo Manifest Audit Task ==="

# Source shared utilities
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous artifacts
OUTPUT_FILE="/home/ga/Desktop/marine_manifest.csv"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing existing output file..."
    rm "$OUTPUT_FILE"
fi

# 3. Ensure Firefox is running and valid
# Using the utility function from task_utils.sh if available, otherwise manual
if command -v launch_firefox_to_url >/dev/null; then
    launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga"
else
    # Fallback implementation
    echo "Launching Firefox manually..."
    pkill -u ga -f firefox 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO"; then
            echo "Firefox window detected."
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
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="