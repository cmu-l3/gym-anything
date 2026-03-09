#!/bin/bash
set -e
echo "=== Setting up Kruskal-Wallis Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure JASP is not running initially
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# 3. Prepare the dataset
# Ensure the dataset exists (space-free filename is critical for JASP flatpak launch)
DATA_DIR="/home/ga/Documents/JASP"
mkdir -p "$DATA_DIR"
DATASET="$DATA_DIR/ToothGrowth.csv"

if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jasp_datasets..."
    # Check if source exists, if not try to download or create dummy for environment stability
    if [ -f "/opt/jasp_datasets/Tooth Growth.csv" ]; then
        cp "/opt/jasp_datasets/Tooth Growth.csv" "$DATASET"
    elif [ -f "/opt/jasp_datasets/ToothGrowth.csv" ]; then
        cp "/opt/jasp_datasets/ToothGrowth.csv" "$DATASET"
    else
        echo "ERROR: Source dataset not found in /opt/jasp_datasets"
        exit 1
    fi
    chown ga:ga "$DATASET"
fi

echo "Dataset ready at $DATASET"

# 4. Clean up previous run artifacts
rm -f "$DATA_DIR/ToothGrowth_KruskalWallis.jasp"
rm -f "$DATA_DIR/kruskal_wallis_report.txt"

# 5. Launch JASP with the dataset
echo "Launching JASP..."
# Uses setsid so the process survives when su exits
# launch-jasp wrapper handles the flatpak invocation
su - ga -c "setsid /usr/local/bin/launch-jasp $DATASET > /tmp/jasp_launch.log 2>&1 &"

# 6. Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 7. Maximize and focus window
sleep 2
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 8. Capture initial state screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="