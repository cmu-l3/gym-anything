#!/bin/bash
set -e
echo "=== Setting up PCA Score Extraction Workflow ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# 3. Ensure the dataset exists and is clean
DATA_DIR="/home/ga/Documents/Jamovi"
mkdir -p "$DATA_DIR"
DATASET="$DATA_DIR/BFI25.csv"

# Copy fresh dataset from the prepared location
if [ -f "/opt/jamovi_datasets/BFI25.csv" ]; then
    cp "/opt/jamovi_datasets/BFI25.csv" "$DATASET"
elif [ -f "/opt/jamovi_datasets/bfi.csv" ]; then
    # Fallback if BFI25 wasn't pre-generated (it should be in post_start)
    python3 /opt/jamovi_datasets/extract_bfi25.py
    cp "/opt/jamovi_datasets/BFI25.csv" "$DATASET"
fi

chown ga:ga "$DATASET"
chmod 644 "$DATASET"

echo "Dataset prepared: $DATASET"

# 4. Remove previous results if they exist
rm -f "$DATA_DIR/PCA_Workflow.omv"
rm -f "$DATA_DIR/neuroticism_age_corr.txt"

# 5. Launch Jamovi with the dataset
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi_launch.log 2>&1 &"

# 6. Wait for Jamovi window
echo "Waiting for Jamovi window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "BFI25"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done
sleep 5

# 7. Maximize the window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Ensure it's focused
DISPLAY=:1 wmctrl -a ":ACTIVE:" 2>/dev/null || true

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="