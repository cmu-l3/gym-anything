#!/bin/bash
set -e
echo "=== Setting up check_ancova_homogeneity_exam task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
rm -f /home/ga/Documents/Jamovi/HomogeneityCheck.omv
rm -f /home/ga/Documents/Jamovi/assumption_report.txt
rm -f /tmp/task_result.json

# 3. Ensure dataset exists
DATASET_SOURCE="/opt/jamovi_datasets/Exam Anxiety.csv"
DATASET_DEST="/home/ga/Documents/Jamovi/ExamAnxiety.csv"

mkdir -p "$(dirname "$DATASET_DEST")"

if [ ! -f "$DATASET_DEST" ]; then
    echo "Copying dataset..."
    if [ -f "$DATASET_SOURCE" ]; then
        cp "$DATASET_SOURCE" "$DATASET_DEST"
    else
        # Fallback if opt missing (shouldn't happen in this env)
        echo "Warning: Source dataset missing, checking backup..."
        if [ -f "/home/ga/Documents/Jamovi/ExamAnxiety.csv" ]; then
            echo "Dataset already present."
        else
            echo "ERROR: Dataset not found."
            exit 1
        fi
    fi
    chown ga:ga "$DATASET_DEST"
fi

# 4. Launch Jamovi with the dataset
echo "Launching Jamovi..."
# Kill any existing instance first
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch using the wrapper script (handles setsid/flatpak args)
# Pass the dataset path to auto-load it
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET_DEST' > /tmp/jamovi_launch.log 2>&1 &"

# 5. Wait for window and maximize
echo "Waiting for Jamovi window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ExamAnxiety"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize the window (CRITICAL for VLM visibility)
# Note: Title usually contains the filename "ExamAnxiety"
DISPLAY=:1 wmctrl -r "ExamAnxiety" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ExamAnxiety" 2>/dev/null || true

# 6. Capture initial state screenshot
sleep 5 # Wait for UI to render
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="