#!/bin/bash
set -e
echo "=== Setting up Cell Spacing Analysis Task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Create directory structure
su - ga -c "mkdir -p /home/ga/Fiji_Data/workspace"
su - ga -c "mkdir -p /home/ga/Fiji_Data/results/spacing"

# 3. Prepare Input Data
# We look for BBBC005 data downloaded by the environment install script.
# If not found (unlikely in correct env), we download a fallback.
SOURCE_DIR="/opt/fiji_samples/BBBC005"
WORK_FILE="/home/ga/Fiji_Data/workspace/cell_image.tif"

if [ -d "$SOURCE_DIR" ]; then
    # Pick a specific image. BBBC005 file naming: BBBC005_v1_images/SIMCEPImages_A05_C18_F1_s05_w1.TIF
    # We want a medium density image. "C52" represents cell count ~52.
    # Note: Environment install script might unzip to a subdir. Find any TIF.
    SELECTED_IMAGE=$(find "$SOURCE_DIR" -name "*C52*w1.TIF" | head -n 1)
    
    # Fallback if specific density not found
    if [ -z "$SELECTED_IMAGE" ]; then
        SELECTED_IMAGE=$(find "$SOURCE_DIR" -name "*.TIF" | head -n 1)
    fi
else
    echo "Warning: Source directory not found. Using simple fallback."
    SELECTED_IMAGE=""
fi

if [ -n "$SELECTED_IMAGE" ] && [ -f "$SELECTED_IMAGE" ]; then
    echo "Copying $SELECTED_IMAGE to workspace..."
    cp "$SELECTED_IMAGE" "$WORK_FILE"
else
    echo "Downloading fallback image..."
    # Fallback: Download a specific sample from BBBC via curl if local missing
    curl -L -o "$WORK_FILE" "https://data.broadinstitute.org/bbbc/BBBC005/BBBC005_v1_images/SIMCEPImages_A05_C53_F1_s05_w1.TIF" || \
    # Last resort: use blobs sample from Fiji
    cp /opt/fiji_samples/blobs.gif "$WORK_FILE" 2>/dev/null || true
fi

# Ensure permissions
chown ga:ga "$WORK_FILE"
chmod 644 "$WORK_FILE"

# 4. Clean previous results
rm -f /home/ga/Fiji_Data/results/spacing/* 2>/dev/null || true

# 5. Launch Fiji
echo "Launching Fiji..."
if pgrep -f "fiji" > /dev/null; then
    echo "Fiji already running."
else
    su - ga -c "DISPLAY=:1 /usr/local/bin/fiji &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej"; then
            echo "Fiji window detected."
            break
        fi
        sleep 1
    done
fi

# 6. Configure Window
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="