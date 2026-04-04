#!/bin/bash
set -e
echo "=== Setting up Logistic Regression Titanic Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
rm -f /home/ga/Documents/Jamovi/TitanicLogistic.omv
rm -f /home/ga/Documents/Jamovi/logistic_report.txt

# Verify dataset exists
DATASET="/home/ga/Documents/Jamovi/TitanicSurvival.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from backup..."
    cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATASET" 2>/dev/null || true
    chown ga:ga "$DATASET"
fi

# Launch Jamovi (starting empty as per task description)
# The agent must open the file themselves.
echo "Launching Jamovi..."
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
            echo "Jamovi window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize window
sleep 5
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="