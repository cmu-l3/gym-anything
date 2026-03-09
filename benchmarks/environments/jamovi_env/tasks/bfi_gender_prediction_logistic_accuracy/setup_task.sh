#!/bin/bash
set -e
echo "=== Setting up BFI Gender Prediction task ==="

# 1. Timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure Dataset Exists
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATASET" ]; then
    echo "Regenerating BFI25.csv from source..."
    # Fallback if setup_jamovi.sh didn't run or file was deleted
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
        mv "/home/ga/Documents/Jamovi/BFI25.csv" "$DATASET" 2>/dev/null || true
    fi
fi

# Set permissions
chown ga:ga "$DATASET" 2>/dev/null || true
chmod 644 "$DATASET" 2>/dev/null || true

# 3. Clean up previous artifacts
rm -f "/home/ga/Documents/Jamovi/BFI_Gender_Prediction.omv"
rm -f "/home/ga/Documents/Jamovi/model_accuracy_report.txt"

# 4. Start Jamovi (Blank state as per description)
# We start it empty so the agent has to open the file.
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    echo "Starting Jamovi..."
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
            echo "Jamovi window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Maximize and Focus
# Jamovi window title is often "jamovi" or "Untitled" when blank
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# 6. Capture Initial State
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="