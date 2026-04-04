#!/bin/bash
set -e
echo "=== Setting up naive_bayes_dose_classification task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists
DATASET="/home/ga/Documents/JASP/ToothGrowth.csv"
# The environment setup usually puts it there, but we verify
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from /opt/jasp_datasets..."
    mkdir -p /home/ga/Documents/JASP
    # Use the one from setup_jasp.sh logic or fallback to opt
    if [ -f "/opt/jasp_datasets/Tooth Growth.csv" ]; then
        cp "/opt/jasp_datasets/Tooth Growth.csv" "$DATASET"
    else
        # Fallback download if missing (should not happen in correct env)
        wget -q -O "$DATASET" "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/3.%20ANOVA/Tooth%20Growth.csv"
    fi
    chown ga:ga "$DATASET"
fi

# Clean up any previous run artifacts
rm -f "/home/ga/Documents/JASP/NaiveBayesDose.jasp"
rm -f "/home/ga/Documents/JASP/naive_bayes_report.txt"

echo "Dataset ready: $DATASET"

# Kill any running JASP instance to start fresh
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 3

# Launch JASP with the dataset
# CRITICAL: Use setsid and the wrapper to ensure it survives su exit
# QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox is handled by /usr/local/bin/launch-jasp
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Wait a bit for the data to actually load into the grid
sleep 5

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="