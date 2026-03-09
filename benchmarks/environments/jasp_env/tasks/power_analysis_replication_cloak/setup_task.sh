#!/bin/bash
set -e
echo "=== Setting up Power Analysis Task ==="

# 1. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 2. Cleanup Previous Run Artifacts
rm -f "/home/ga/Documents/JASP/PowerAnalysis.jasp"
rm -f "/home/ga/Documents/JASP/power_report.txt"
rm -f "/tmp/task_result.json"

# 3. Ensure Dataset Exists
DATASET_SOURCE="/opt/jasp_datasets/Invisibility Cloak.csv"
DATASET_DEST="/home/ga/Documents/JASP/InvisibilityCloak.csv"

mkdir -p /home/ga/Documents/JASP
if [ -f "$DATASET_SOURCE" ]; then
    cp "$DATASET_SOURCE" "$DATASET_DEST"
    chown ga:ga "$DATASET_DEST"
    echo "Dataset prepared at $DATASET_DEST"
else
    echo "ERROR: Source dataset not found at $DATASET_SOURCE"
    exit 1
fi

# 4. Start JASP (Clean State)
# We start JASP empty so the agent has to open the file.
# This proves they can navigate the UI.
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    echo "Starting JASP..."
    su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"
    
    # Wait for JASP window
    echo "Waiting for JASP window..."
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
            echo "JASP window detected."
            break
        fi
        sleep 1
    done
    sleep 5 # Extra buffer for UI to render
fi

# 5. Maximize JASP Window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 6. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="