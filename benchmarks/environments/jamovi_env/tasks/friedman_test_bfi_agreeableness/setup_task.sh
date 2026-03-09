#!/bin/bash
set -e
echo "=== Setting up Friedman Test Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the BFI25 dataset exists
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring BFI25.csv..."
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
    else
        echo "ERROR: Extraction script not found!"
        exit 1
    fi
    # Ensure ownership
    chown ga:ga "$DATASET" 2>/dev/null || true
fi

# Remove any previous output file to ensure a fresh run
rm -f "/home/ga/Documents/Jamovi/FriedmanAgreeableness.omv"

# Kill any existing Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi (Empty State)
# The task requires the agent to open the file themselves
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
sleep 5
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Dismiss start screen if present (Esc usually works)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="