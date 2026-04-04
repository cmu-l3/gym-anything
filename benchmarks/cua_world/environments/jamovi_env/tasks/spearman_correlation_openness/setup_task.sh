#!/bin/bash
set -e
echo "=== Setting up Spearman Correlation task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f "/home/ga/Documents/Jamovi/spearman_openness_report.txt"
rm -f /tmp/task_result.json

# Kill any running Jamovi instance to ensure fresh state
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Ensure the BFI25 dataset exists
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATASET" ]; then
    echo "Regenerating BFI25 dataset..."
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
    else
        echo "ERROR: Extraction script not found!"
        exit 1
    fi
    # Move to correct location if script output differs
    if [ -f "/home/ga/Documents/Jamovi/BFI25.csv" ]; then
        echo "Dataset generated successfully."
    else
        echo "ERROR: Dataset generation failed."
        exit 1
    fi
fi
chown ga:ga "$DATASET"

# Open Jamovi with the dataset loaded
echo "Launching Jamovi with $DATASET..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi_task.log 2>&1 &"

# Wait for Jamovi to initialize
echo "Waiting for Jamovi window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize the window (Title usually contains the filename "BFI25")
# We use :ACTIVE: after focusing or try to find by name
WID=$(DISPLAY=:1 wmctrl -l | grep -i "BFI25" | head -n 1 | awk '{print $1}')
if [ -z "$WID" ]; then
    # Fallback to any Jamovi window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "jamovi" | head -n 1 | awk '{print $1}')
fi

if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    sleep 1
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    echo "Window maximized."
fi

# Dismiss any startup dialogs (Welcome screen)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="