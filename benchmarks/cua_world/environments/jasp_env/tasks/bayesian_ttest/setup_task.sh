#!/bin/bash
set -e
echo "=== Setting up Bayesian T-Test Task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous run artifacts
rm -f "/home/ga/Documents/JASP/InvisibilityCloak_BayesianTTest.jasp"
rm -f "/home/ga/Documents/JASP/bayesian_ttest_results.txt"

# 3. Ensure Dataset Exists
DATASET="/home/ga/Documents/JASP/InvisibilityCloak.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from backup..."
    cp "/opt/jasp_datasets/Invisibility Cloak.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# 4. Start JASP with the dataset
echo "Starting JASP..."
# Kill any existing instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Launch JASP (using system-wide launcher wrapper if available, else flatpak directly)
if [ -f /usr/local/bin/launch-jasp ]; then
    su - ga -c "setsid /usr/local/bin/launch-jasp \"$DATASET\" > /tmp/jasp_launch.log 2>&1 &"
else
    su - ga -c "setsid flatpak run org.jaspstats.JASP \"$DATASET\" > /tmp/jasp_launch.log 2>&1 &"
fi

# 5. Wait for JASP window
echo "Waiting for JASP to load..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 6. Maximize and Focus
echo "Configuring window..."
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 7. Dismiss startup dialogs (Welcome screen / Updates)
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 8. Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="