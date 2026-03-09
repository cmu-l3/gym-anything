#!/bin/bash
set -e
echo "=== Setting up regression_diagnostics_exam task ==="

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure dataset exists and is clean
DATASET_SOURCE="/opt/jamovi_datasets/Exam Anxiety.csv"
DATASET_DEST="/home/ga/Documents/Jamovi/ExamAnxiety.csv"

mkdir -p /home/ga/Documents/Jamovi
if [ -f "$DATASET_SOURCE" ]; then
    cp "$DATASET_SOURCE" "$DATASET_DEST"
    chown ga:ga "$DATASET_DEST"
    chmod 644 "$DATASET_DEST"
else
    echo "ERROR: Source dataset not found at $DATASET_SOURCE"
    exit 1
fi

# 3. Clean up previous outputs
rm -f "/home/ga/Documents/Jamovi/ExamAnxiety_Diagnostics.omv"
rm -f "/home/ga/Documents/Jamovi/diagnostics_report.txt"

# 4. Start Jamovi (empty state)
# We start it empty so the agent has to perform the "Open" action as part of the workflow
echo "Starting Jamovi..."
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

# 5. Maximize and focus
sleep 5
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="