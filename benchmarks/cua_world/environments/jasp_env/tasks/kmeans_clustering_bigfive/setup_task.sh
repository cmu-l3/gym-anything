#!/bin/bash
echo "=== Setting up JASP K-Means Task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
OUTPUT_FILE="/home/ga/Documents/JASP/BigFive_KMeans.jasp"
rm -f "$OUTPUT_FILE" 2>/dev/null || true

# 3. Ensure Dataset Exists
DATASET_SOURCE="/opt/jasp_datasets/Big Five Personality Traits.csv"
DATASET_DEST="/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"

# Ensure directory exists
mkdir -p /home/ga/Documents/JASP
chown ga:ga /home/ga/Documents/JASP

# Copy dataset if missing (handle spaces in source, no spaces in dest)
if [ ! -f "$DATASET_DEST" ]; then
    echo "Restoring dataset..."
    cp "$DATASET_SOURCE" "$DATASET_DEST" 2>/dev/null || \
    wget -q -O "$DATASET_DEST" "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/4.%20Regression/Big%20Five%20Personality%20Traits.csv"
    chown ga:ga "$DATASET_DEST"
fi

# 4. Launch JASP with Dataset
# Kill existing
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Launch
echo "Launching JASP..."
# Use setsid to detach from shell, ensure no-sandbox flags via launcher
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET_DEST' > /tmp/jasp_launch.log 2>&1 &"

# 5. Wait for Window and Initialize
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window found."
        break
    fi
    sleep 1
done

# Small buffer for UI to load
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss "Check for updates" or welcome dialogs if they appear
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Capture Initial State
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="