#!/bin/bash
set -e
echo "=== Setting up Jaccard Overlap Quantification task ==="

# 1. Define paths
RAW_DIR="/home/ga/Fiji_Data/raw/jaccard"
RESULTS_DIR="/home/ga/Fiji_Data/results/jaccard"
SOURCE_DIR="/opt/fiji_samples/BBBC005"

# 2. Create directories
mkdir -p "$RAW_DIR"
mkdir -p "$RESULTS_DIR"

# 3. Clean previous results
rm -f "$RESULTS_DIR"/*

# 4. Prepare Data
# We select a specific pair from the BBBC005 dataset installed in the environment
# If specific files aren't found, we fall back to downloading or generating dummy data for safety
echo "Preparing image data..."

if [ -d "$SOURCE_DIR" ]; then
    # Try to find a matching pair
    # BBBC005 pattern: SIMCEP_images_A01_t15_p01_w1.TIF
    FILE_W1=$(find "$SOURCE_DIR" -name "*w1.TIF" | head -n 1)
    
    if [ -n "$FILE_W1" ]; then
        FILE_W2="${FILE_W1/w1.TIF/w2.TIF}"
        
        if [ -f "$FILE_W2" ]; then
            cp "$FILE_W1" "$RAW_DIR/channel_1.tif"
            cp "$FILE_W2" "$RAW_DIR/channel_2.tif"
            echo "Copied real BBBC005 images."
        else
            echo "Warning: Matching w2 file not found for $FILE_W1"
        fi
    fi
fi

# Fallback: Download specific samples if local copy failed
if [ ! -f "$RAW_DIR/channel_1.tif" ]; then
    echo "Downloading samples from Broad Institute..."
    wget -q "https://data.broadinstitute.org/bbbc/BBBC005/BBBC005_v1_images/SIMCEP_images_A01_t15_p01_w1.TIF" -O "$RAW_DIR/channel_1.tif"
    wget -q "https://data.broadinstitute.org/bbbc/BBBC005/BBBC005_v1_images/SIMCEP_images_A01_t15_p01_w2.TIF" -O "$RAW_DIR/channel_2.tif"
fi

# 5. Set permissions
chown -R ga:ga "/home/ga/Fiji_Data"

# 6. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 7. Launch Fiji
echo "Launching Fiji..."
if [ -f "/home/ga/launch_fiji.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
else
    su - ga -c "DISPLAY=:1 fiji" &
fi

# Wait for Fiji window
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null 2>&1; then
        echo "Fiji window detected."
        # Maximize
        DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="