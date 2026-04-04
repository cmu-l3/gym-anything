#!/bin/bash
set -e
echo "=== Setting up CFA task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure the BFI25 dataset exists
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATASET" ]; then
    echo "ERROR: BFI25.csv not found at $DATASET"
    # Fallback: check if script exists to generate it
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        echo "Attempting to generate dataset..."
        python3 /opt/jamovi_datasets/extract_bfi25.py
    else
        exit 1
    fi
fi

# Ensure dataset size is reasonable (real data)
SIZE=$(stat -c%s "$DATASET" 2>/dev/null || echo 0)
if [ "$SIZE" -lt 50000 ]; then
    echo "ERROR: BFI25.csv is too small ($SIZE bytes). Likely corrupted."
    exit 1
fi
echo "Dataset verified: $DATASET ($SIZE bytes)"

# Clean up previous artifacts
rm -f /home/ga/Documents/Jamovi/BFI25_CFA.omv
rm -f /home/ga/Documents/Jamovi/CFA_results.txt
rm -f /tmp/task_result.json

# Kill any existing Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Launch Jamovi (empty state, agent must open file)
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_task.log 2>&1 &"

# Wait for window
echo "Waiting for Jamovi window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "jamovi"; then
        echo "Window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== CFA task setup complete ==="