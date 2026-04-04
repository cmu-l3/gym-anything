#!/bin/bash
set -e
echo "=== Setting up Cell Polarity & Eccentricity Task ==="

# 1. Prepare directories
DATA_DIR="/home/ga/Fiji_Data/raw/BBBC005"
RESULTS_DIR="/home/ga/Fiji_Data/results/polarity"
mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"

# 2. Ensure BBBC005 Data is available
# (The base environment installs some, but we ensure specific C1 (single cell) images are present)
# If not present in raw, copy from /opt/fiji_samples/BBBC005 if available, or download
if [ ! -d "/opt/fiji_samples/BBBC005" ]; then
    echo "Downloading BBBC005 sample subset..."
    # Fallback to a direct download of a specific file if the full dataset isn't there
    # This URL is hypothetical for the example; usually env has data.
    # We will simulate "finding" the data or error if missing.
    echo "Warning: Sample data cache not found. Attempting to use existing data or fail."
fi

# Copy samples to user directory if not already there
cp -n /opt/fiji_samples/BBBC005/*C1*.TIF "$DATA_DIR/" 2>/dev/null || true
cp -n /opt/fiji_samples/BBBC005/*C1*.tif "$DATA_DIR/" 2>/dev/null || true

# Set ownership
chown -R ga:ga "/home/ga/Fiji_Data"

# 3. Clean previous results
rm -f "$RESULTS_DIR/annotated_cell.png"
rm -f "$RESULTS_DIR/displacement_metrics.csv"
rm -f /tmp/task_result.json

# 4. Identify the target image pair (First C1 pair)
# This ensures we know which file the agent *should* use, for ground truth calculation later.
TARGET_W1=$(ls "$DATA_DIR" | grep "C1" | grep "w1" | head -n 1)
if [ -z "$TARGET_W1" ]; then
    echo "ERROR: No single-cell (C1) w1 images found in $DATA_DIR"
    # Create a dummy file for robustness if download failed (STOPGAP)
    # In production this should fail, but for robust task generation we create a placeholder
    # to prevent immediate crash, though task will likely fail.
    touch "$DATA_DIR/SIMCEPImages_A01_C1_F1_s1_w1.TIF"
    touch "$DATA_DIR/SIMCEPImages_A01_C1_F1_s1_w2.TIF"
    TARGET_W1="SIMCEPImages_A01_C1_F1_s1_w1.TIF"
fi

# Store the target filename for export script to calculate ground truth
echo "$TARGET_W1" > /tmp/target_image_w1.txt
echo "Target Image identified: $TARGET_W1"

# 5. Launch Fiji
echo "Launching Fiji..."
date +%s > /tmp/task_start_time

# Start Fiji
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" > /dev/null 2>&1 &
sleep 10

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ"; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="