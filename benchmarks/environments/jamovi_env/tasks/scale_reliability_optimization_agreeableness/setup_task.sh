#!/bin/bash
set -e
echo "=== Setting up scale_reliability_optimization_agreeableness task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Ensure the dataset exists
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATASET" ]; then
    echo "Dataset missing at $DATASET. Attempting to generate..."
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
    else
        echo "ERROR: Extraction script not found."
        # Fail gracefully? Or create dummy? Better to fail setup.
        exit 1
    fi
    # Verify generation
    if [ ! -f "$DATASET" ]; then
        echo "ERROR: Failed to generate dataset."
        exit 1
    fi
    chown ga:ga "$DATASET"
fi

echo "Dataset ready: $DATASET"

# Launch Jamovi with the dataset pre-loaded
# Using setsid to detach from the shell, ensuring it survives
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi_launch.log 2>&1 &"

# Wait for Jamovi window to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "BFI25"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# Additional sleep to ensure UI is responsive
sleep 10

# Maximize the Jamovi window
# Identifying window by part of the filename "BFI25" usually works if loaded
DISPLAY=:1 wmctrl -r "BFI25" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "BFI25" 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="