#!/bin/bash
# Setup script for Wound Healing Analysis task
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up Wound Healing Analysis Task ==="

# Define directories
DATA_DIR="/home/ga/ImageJ_Data/raw"
RESULTS_DIR="/home/ga/ImageJ_Data/results"

mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "/home/ga/ImageJ_Data"

# Clean up previous run
rm -f "$RESULTS_DIR/wound_mask.tif"
rm -f "$RESULTS_DIR/wound_results.csv"
rm -f /tmp/task_result.json

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Prepare Data (Real Phase-Contrast Image)
# Source: Broad Bioimage Benchmark Collection (BBBC030)
TARGET_IMG="$DATA_DIR/scratch_assay.tif"

if [ ! -f "$TARGET_IMG" ]; then
    echo "Downloading real scratch assay data..."
    
    # Create temp dir for download
    TMP_DL="/tmp/bbbc030_dl"
    mkdir -p "$TMP_DL"
    
    # Download zip (BBBC030 is small enough)
    # Using a reliable mirror or direct link. BBBC030 images are often .png
    # We will try to download a specific sample if possible, or the zip
    
    # URL for BBBC030v1 images
    URL="https://data.broadinstitute.org/bbbc/BBBC030/BBBC030_v1_images.zip"
    
    if wget -q --timeout=60 -O "$TMP_DL/images.zip" "$URL"; then
        echo "Download successful, extracting..."
        unzip -q -j "$TMP_DL/images.zip" -d "$TMP_DL"
        
        # Find a suitable image (look for one that isn't the ground truth)
        # Usually named like '2009_09_03_...w1.png'
        SRC_IMG=$(find "$TMP_DL" -name "*w1*.png" -o -name "*w1*.tif" | head -n 1)
        
        if [ -n "$SRC_IMG" ]; then
            echo "Selected image: $(basename "$SRC_IMG")"
            # Convert to TIF for consistency using ImageMagick
            convert "$SRC_IMG" -type Grayscale -depth 8 "$TARGET_IMG"
        else
            echo "WARNING: No suitable image found in zip."
        fi
    else
        echo "WARNING: Download failed."
    fi
    
    # Fallback if download failed or extraction failed: Generate a synthetic texture image
    # This ensures the task is runnable even if the external link is down
    if [ ! -f "$TARGET_IMG" ]; then
        echo "Generating synthetic phase-contrast fallback..."
        # Create noise (cells) and a smooth rectangle (wound)
        # 1. Create noise
        convert -size 512x512 xc:gray +noise Gaussian -blur 0x1 /tmp/noise.png
        # 2. Create mask (wound)
        convert -size 512x512 xc:black -fill white -draw "rectangle 200,0 312,512" /tmp/mask.png
        # 3. Composite: Smooth gray in wound, noise in cells
        convert /tmp/noise.png /tmp/mask.png -compose SrcOver -composite "$TARGET_IMG"
        # 4. Blur edges slightly to look realistic
        convert "$TARGET_IMG" -blur 0x1 "$TARGET_IMG"
    fi
    
    # Cleanup
    rm -rf "$TMP_DL"
fi

# Ensure permissions
chown ga:ga "$TARGET_IMG"

# 2. Start Fiji
echo "Ensuring clean Fiji state..."
kill_fiji 2>/dev/null || true
sleep 2

# Launch Fiji (not opening image yet - agent must do it)
FIJI_PATH=$(find_fiji_executable)
if [ -n "$FIJI_PATH" ]; then
    echo "Launching Fiji..."
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "ImageJ\|Fiji"; then
            echo "Fiji started."
            break
        fi
        sleep 1
    done
    
    # Maximize
    WID=$(get_fiji_window_id)
    if [ -n "$WID" ]; then
        maximize_window "$WID"
        focus_window "$WID"
    fi
else
    echo "ERROR: Fiji executable not found."
    exit 1
fi

# 3. Initial Screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="