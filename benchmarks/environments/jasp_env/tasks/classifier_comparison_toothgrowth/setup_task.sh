#!/bin/bash
set -e
echo "=== Setting up Classifier Comparison Task ==="

# 1. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Dataset Exists
DATA_DIR="/home/ga/Documents/JASP"
mkdir -p "$DATA_DIR"
SOURCE_DATA="/opt/jasp_datasets/Tooth Growth.csv"
TARGET_DATA="$DATA_DIR/ToothGrowth.csv"

if [ -f "$SOURCE_DATA" ]; then
    cp "$SOURCE_DATA" "$TARGET_DATA"
    echo "Copied dataset to $TARGET_DATA"
else
    echo "ERROR: Source data not found at $SOURCE_DATA"
    # Fallback download if missing (safety net)
    wget -q -O "$TARGET_DATA" "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/3.%20ANOVA/Tooth%20Growth.csv"
fi

# Ensure permissions
chown -R ga:ga "$DATA_DIR"

# 3. Clean up previous run artifacts
rm -f "$DATA_DIR/Classifier_Comparison.jasp"
rm -f "$DATA_DIR/model_performance.txt"

# 4. Start JASP (Empty)
# We start JASP without arguments so the agent has to load the file
echo "Starting JASP..."
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
            echo "JASP window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Maximize Window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 6. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="