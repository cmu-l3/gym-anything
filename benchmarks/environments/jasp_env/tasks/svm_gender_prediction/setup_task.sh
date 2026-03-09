#!/bin/bash
echo "=== Setting up SVM Gender Prediction Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing JASP instances to ensure a clean start
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

# Ensure the dataset exists in the Documents folder
# We use the system-wide pre-downloaded datasets
DATA_SOURCE="/opt/jasp_datasets/Big Five Personality Traits.csv"
DATA_DEST="/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"

mkdir -p /home/ga/Documents/JASP

if [ -f "$DATA_SOURCE" ]; then
    echo "Copying dataset to workspace..."
    cp "$DATA_SOURCE" "$DATA_DEST"
    chown ga:ga "$DATA_DEST"
    chmod 644 "$DATA_DEST"
else
    echo "ERROR: Source dataset not found at $DATA_SOURCE"
    # Fallback/Emergency creation (should not happen if env is built correctly)
    echo "Gender,Agreeableness,Conscientiousness,Extraversion,Neuroticism,Openness" > "$DATA_DEST"
    echo "Male,3.5,4.0,2.5,3.0,3.5" >> "$DATA_DEST"
fi

# Remove previous outputs if they exist
rm -f "/home/ga/Documents/JASP/SVM_Gender_Analysis.jasp"
rm -f "/home/ga/Documents/JASP/svm_performance_report.txt"

# Launch JASP with the dataset pre-loaded
# Using the wrapper script defined in environment setup
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp \"$DATA_DEST\" > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window to appear
echo "Waiting for JASP to load..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Give it a few more seconds to fully render the UI
sleep 5

# Maximize the JASP window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Dismiss any potential 'Check for Updates' or welcome dialogs
# Press Escape a couple of times
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="