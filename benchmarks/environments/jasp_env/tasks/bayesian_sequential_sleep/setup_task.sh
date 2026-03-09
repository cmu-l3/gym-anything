#!/bin/bash
echo "=== Setting up bayesian_sequential_sleep task ==="

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous run artifacts
rm -f /home/ga/Documents/JASP/Sleep_Sequential_Bayes.jasp
rm -f /tmp/task_result.json

# 3. Ensure Dataset Exists
DATASET_SOURCE="/opt/jasp_datasets/Sleep.csv"
DATASET_DEST="/home/ga/Documents/JASP/Sleep.csv"
mkdir -p /home/ga/Documents/JASP

if [ ! -f "$DATASET_DEST" ]; then
    if [ -f "$DATASET_SOURCE" ]; then
        cp "$DATASET_SOURCE" "$DATASET_DEST"
        echo "Copied Sleep.csv to Documents"
    else
        echo "ERROR: Sleep.csv not found in /opt/jasp_datasets"
        exit 1
    fi
fi
chown ga:ga "$DATASET_DEST"

# 4. Start JASP with the dataset
# Kill any existing instances first
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

echo "Launching JASP..."
# Use setsid to detach so it survives su exit
# The launcher script handles the --no-sandbox flags required for JASP
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET_DEST' > /tmp/jasp_launch.log 2>&1 &"

# 5. Wait for JASP window
echo "Waiting for JASP to load..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 6. Maximize and Focus
sleep 5 # Wait for UI to render
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 7. Dismiss initial dialogs if any (simulating Escape/Enter)
sleep 2
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true

# 8. Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="