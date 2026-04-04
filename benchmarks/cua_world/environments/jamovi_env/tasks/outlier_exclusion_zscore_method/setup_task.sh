#!/bin/bash
set -e
echo "=== Setting up Outlier Exclusion Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# 3. Ensure Dataset Exists
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATASET" ]; then
    echo "Dataset missing. Attempting to restore from /opt/jamovi_datasets..."
    # The environment setup script creates BFI25.csv via a python script. 
    # If missing, we assume the environment might be fresh and try to find source.
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
        mv /home/ga/Documents/Jamovi/BFI25.csv "$DATASET" 2>/dev/null || true
    else
        echo "CRITICAL ERROR: Data generation script not found."
        exit 1
    fi
fi
chown ga:ga "$DATASET"
chmod 644 "$DATASET"
echo "Dataset verified at $DATASET"

# 4. Remove previous outputs if they exist
rm -f "/home/ga/Documents/Jamovi/Age_Outlier_Removal.omv"
rm -f "/home/ga/Documents/Jamovi/outlier_report.txt"

# 5. Launch Jamovi with the dataset
echo "Launching Jamovi..."
# Use setsid to detach from the shell so it persists
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi.log 2>&1 &"

# 6. Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "BFI25"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# 7. Maximize the window (Crucial for VLM visibility)
# Note: Jamovi window title usually reflects the filename
sleep 2
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Capture Initial State Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="