#!/bin/bash
set -e
echo "=== Setting up logistic_feature_creation_hierarchical task ==="

# Source utilities if available, otherwise define basics
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jamovi directory exists
mkdir -p /home/ga/Documents/Jamovi
chown ga:ga /home/ga/Documents/Jamovi

# Ensure dataset exists
DATASET="/home/ga/Documents/Jamovi/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    # Check source locations
    if [ -f "/opt/jamovi_datasets/Exam Anxiety.csv" ]; then
        cp "/opt/jamovi_datasets/Exam Anxiety.csv" "$DATASET"
    elif [ -f "/opt/jamovi_datasets/ExamAnxiety.csv" ]; then
        cp "/opt/jamovi_datasets/ExamAnxiety.csv" "$DATASET"
    else
        echo "ERROR: Exam Anxiety dataset not found in /opt/jamovi_datasets"
        # Create dummy if absolutely necessary (should not happen in valid env)
        echo "Code,Revise,Exam,Anxiety,Gender" > "$DATASET"
        echo "1,10,60,40,Male" >> "$DATASET"
    fi
    chown ga:ga "$DATASET"
fi

# Clean up previous results
rm -f "/home/ga/Documents/Jamovi/ExamPass_LogReg.omv"
rm -f "/home/ga/Documents/Jamovi/model_results.txt"

# Kill any existing Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi (Start empty as per description "Jamovi is open with a blank spreadsheet")
# Use the system-wide launcher we created in env setup
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi.log 2>&1 &"

# Wait for Jamovi window
echo "Waiting for Jamovi to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize window
sleep 5
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss welcome dialogs if present (Esc, Enter)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="