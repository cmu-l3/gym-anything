#!/bin/bash
set -e
echo "=== Setting up Risk Ratio Titanic task ==="

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure dataset exists and is clean
DATASET="/home/ga/Documents/Jamovi/TitanicSurvival.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset..."
    cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# 3. Clean up any previous run artifacts
rm -f "/home/ga/Documents/Jamovi/Titanic_Risk_Analysis.omv"
rm -f "/home/ga/Documents/Jamovi/risk_value.txt"

# 4. Start Jamovi (using the system-wide launcher wrapper)
# We do NOT load the dataset automatically here, as the task description
# explicitly asks the agent to "Open" the file.
echo "Starting Jamovi..."
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi.log 2>&1 &"
    
    # Wait for window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
            echo "Jamovi window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Maximize window and focus
# Note: Jamovi's window title often changes based on open file, but initially it's "jamovi"
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# 6. Capture initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="