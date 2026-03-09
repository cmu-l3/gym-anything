#!/bin/bash
set -e

echo "=== Setting up correlation_matrix_exam_anxiety task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the Documents directory exists
mkdir -p /home/ga/Documents/Jamovi

# Prepare the specific dataset for this task
# We copy from the system cache to the user's document folder
SOURCE_DATA="/opt/jamovi_datasets/Exam Anxiety.csv"
DEST_DATA="/home/ga/Documents/Jamovi/ExamAnxiety.csv"

if [ -f "$SOURCE_DATA" ]; then
    cp "$SOURCE_DATA" "$DEST_DATA"
    # Ensure correct ownership
    chown ga:ga "$DEST_DATA"
    echo "Dataset prepared at: $DEST_DATA"
else
    echo "ERROR: Source dataset not found at $SOURCE_DATA"
    exit 1
fi

# Clean up any previous run artifacts
rm -f "/home/ga/Documents/Jamovi/ExamAnxietyCorrelation.omv"
rm -f "/home/ga/Documents/Jamovi/correlation_report.txt"

# Start Jamovi (empty state, user must open file)
# We use the system-wide launcher we created in the environment setup
# Using setsid to detach from the shell so it survives
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    echo "Launching Jamovi..."
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"
    
    # Wait for window to appear (Electron apps can be slow)
    echo "Waiting for Jamovi window..."
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
            echo "Jamovi window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Try generic matching if specific title fails
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="