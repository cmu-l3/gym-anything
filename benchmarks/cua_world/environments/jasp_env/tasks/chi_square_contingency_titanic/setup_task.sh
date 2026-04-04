#!/bin/bash
echo "=== Setting up Chi-Square Titanic Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create Documents directory if it doesn't exist
mkdir -p /home/ga/Documents/JASP

# Download Titanic dataset (Real Data)
TITANIC_PATH="/home/ga/Documents/JASP/Titanic.csv"
TITANIC_URL="https://raw.githubusercontent.com/datasciencedojo/datasets/master/titanic.csv"

if [ ! -f "$TITANIC_PATH" ]; then
    echo "Downloading Titanic dataset..."
    wget -q -O "$TITANIC_PATH" "$TITANIC_URL"
    chmod 644 "$TITANIC_PATH"
    chown ga:ga "$TITANIC_PATH"
fi

# Verify dataset size (should be ~60KB)
SIZE=$(stat -c%s "$TITANIC_PATH" 2>/dev/null || echo 0)
if [ "$SIZE" -lt 1000 ]; then
    echo "ERROR: Dataset download failed or too small"
    exit 1
fi
echo "Dataset ready: $TITANIC_PATH ($SIZE bytes)"

# Kill any existing JASP instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Remove previous result files
rm -f /home/ga/Documents/JASP/chi_square_results.txt
rm -f /home/ga/Documents/JASP/TitanicChiSquare.jasp

# Start JASP with the dataset
# Uses setsid so the process survives when su exits
echo "Starting JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$TITANIC_PATH' > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected"
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Wait for UI to stabilize and load data
sleep 5

# Dismiss any potential "Check for Updates" or welcome dialogs via keypress
# Escape usually closes dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="