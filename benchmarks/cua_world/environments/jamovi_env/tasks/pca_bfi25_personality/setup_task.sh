#!/bin/bash
set -e
echo "=== Setting up PCA BFI-25 task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Verify the BFI25 dataset exists; recreate if missing
BFI_FILE="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$BFI_FILE" ]; then
    echo "Restoring BFI25.csv..."
    mkdir -p /home/ga/Documents/Jamovi
    # Assuming the setup_jamovi.sh created extract_bfi25.py in /opt/jamovi_datasets
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
        mv /home/ga/Documents/Jamovi/BFI25.csv "$BFI_FILE" 2>/dev/null || true
    fi
    chown ga:ga "$BFI_FILE"
fi

# Verify file size/content
BFI_SIZE=$(stat -c%s "$BFI_FILE" 2>/dev/null || echo 0)
if [ "$BFI_SIZE" -lt 500 ]; then
    echo "ERROR: BFI25.csv is too small ($BFI_SIZE bytes)"
    # Fallback to copy if extraction failed
    if [ -f "/opt/jamovi_datasets/bfi.csv" ]; then
         cp "/opt/jamovi_datasets/bfi.csv" "$BFI_FILE"
         chown ga:ga "$BFI_FILE"
    fi
fi

# Remove artifacts from previous runs
rm -f /home/ga/Documents/Jamovi/BFI25_PCA.omv
rm -f /home/ga/Documents/Jamovi/pca_report.txt

# Kill any running Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi with the BFI25 dataset
echo "Launching Jamovi with BFI25.csv..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$BFI_FILE' > /tmp/jamovi_task.log 2>&1 &"

# Wait for Jamovi window to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "jamovi"; then
        echo "Jamovi window detected after ${i}s"
        break
    fi
    sleep 1
done

# Wait extra time for Electron/UI to settle and load data
sleep 15

# Maximize the window
# Use :ACTIVE: if it's the focused window, or find by name. 
# Jamovi window title usually matches the filename.
DISPLAY=:1 wmctrl -r "Jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "BFI25" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any startup dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== PCA BFI-25 task setup complete ==="