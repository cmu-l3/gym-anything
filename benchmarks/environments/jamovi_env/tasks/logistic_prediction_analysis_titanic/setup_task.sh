#!/bin/bash
set -e
echo "=== Setting up Logistic Prediction Analysis task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the Titanic dataset exists in the documents folder
DATA_PATH="/home/ga/Documents/Jamovi/TitanicSurvival.csv"
if [ ! -f "$DATA_PATH" ]; then
    echo "Copying TitanicSurvival.csv..."
    mkdir -p /home/ga/Documents/Jamovi
    # Try different source locations based on environment setup
    if [ -f "/opt/jamovi_datasets/TitanicSurvival.csv" ]; then
        cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATA_PATH"
    elif [ -f "/workspace/data/TitanicSurvival.csv" ]; then
        cp "/workspace/data/TitanicSurvival.csv" "$DATA_PATH"
    fi
    chown ga:ga "$DATA_PATH"
fi

# Ensure Jamovi is running (clean state, no data loaded as per description)
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    echo "Starting Jamovi..."
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"
    
    # Wait for window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
            echo "Jamovi window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Clean up any previous results
rm -f /home/ga/Documents/Jamovi/Titanic_Predictions.omv
rm -f /home/ga/Documents/Jamovi/prediction_summary.txt

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="