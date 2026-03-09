#!/bin/bash
set -e
echo "=== Setting up Mann-Whitney U Test task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous run artifacts
rm -f /home/ga/Documents/JASP/MannWhitneyCloak.jasp
rm -f /home/ga/Documents/JASP/mann_whitney_report.txt

# 3. Verify dataset exists
DATASET="/home/ga/Documents/JASP/InvisibilityCloak.csv"
if [ ! -f "$DATASET" ]; then
    echo "ERROR: Dataset not found at $DATASET"
    # Attempt to restore from backup location if missing
    if [ -f "/opt/jasp_datasets/Invisibility Cloak.csv" ]; then
        echo "Restoring dataset..."
        cp "/opt/jasp_datasets/Invisibility Cloak.csv" "$DATASET"
        chown ga:ga "$DATASET"
    else
        exit 1
    fi
fi

# 4. Kill any existing JASP instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 3

# 5. Launch JASP with the dataset pre-loaded
# We use setsid and the custom launcher to handle the sandbox environment
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_launch.log 2>&1 &"

# 6. Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "jasp"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Allow extra time for the heavy Java/Qt interface to render
sleep 5

# 7. Maximize the window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 8. Focus the window
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 9. Dismiss potential startup dialogs (e.g., 'Check for updates')
# Send Escape key, wait, then Enter key just in case
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# 10. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="