#!/bin/bash
set -e
echo "=== Setting up filtered_anova_toothgrowth task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running JASP instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Ensure the dataset exists and has correct permissions
DATASET="/home/ga/Documents/JASP/ToothGrowth.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from /opt/jasp_datasets..."
    mkdir -p /home/ga/Documents/JASP
    cp "/opt/jasp_datasets/Tooth Growth.csv" "$DATASET" 2>/dev/null || cp "/opt/jasp_datasets/ToothGrowth.csv" "$DATASET"
    chown ga:ga "$DATASET"
    chmod 644 "$DATASET"
fi

# Clean up previous outputs if they exist
rm -f "/home/ga/Documents/JASP/VC_Dose_Analysis.jasp"
rm -f "/home/ga/Documents/JASP/vc_means.txt"

# Launch JASP with the dataset
# Using setsid and nohup to ensure it detaches properly from the shell
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window to appear
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Wait a bit for the UI to fully load the data
sleep 15

# Maximize the window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any potential startup dialogs (Welcome/Updates)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Focus the window again to be sure
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="