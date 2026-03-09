#!/bin/bash
set -e
echo "=== Setting up Reliability Analysis Task ==="

# Source utilities (if available) or define minimal ones
mkdir -p /tmp/task_utils
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Clean up previous artifacts
# ==============================================================================
rm -f "/home/ga/Documents/JASP/Agreeableness_Reliability.jasp"
rm -f "/home/ga/Documents/JASP/reliability_report.txt"

# ==============================================================================
# 2. Ensure Dataset Exists
# ==============================================================================
DATA_DIR="/home/ga/Documents/JASP"
DATASET="$DATA_DIR/BigFivePersonalityTraits.csv"
SOURCE_DATA="/opt/jasp_datasets/Big Five Personality Traits.csv"

mkdir -p "$DATA_DIR"

if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from source..."
    if [ -f "$SOURCE_DATA" ]; then
        cp "$SOURCE_DATA" "$DATASET"
    else
        echo "ERROR: Source dataset not found at $SOURCE_DATA"
        # Fallback to downloading if absolutely necessary, but env should have it
        wget -q -O "$DATASET" "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/4.%20Regression/Big%20Five%20Personality%20Traits.csv"
    fi
fi

# Set permissions
chown -R ga:ga "$DATA_DIR"
chmod 644 "$DATASET"

# ==============================================================================
# 3. Launch JASP
# ==============================================================================
# Kill any existing instances
pkill -f "org.jaspstats.JASP" || true
sleep 2

echo "Launching JASP..."
# Use the launcher script created in env setup which handles sandbox flags
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"

# Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss "Check for updates" or welcome dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus JASP
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="