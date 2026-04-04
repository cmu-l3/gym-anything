#!/bin/bash
echo "=== Setting up cell_nuclear_morphometry_batch task ==="

# Create required directories
echo "Creating directories..."
mkdir -p /home/ga/Fiji_Data/raw/bbbc008
mkdir -p /home/ga/Fiji_Data/results/morphometry

# Clean any previous results to ensure fresh start
echo "Cleaning previous results..."
rm -f /home/ga/Fiji_Data/results/morphometry/nuclear_measurements.csv 2>/dev/null || true
rm -f /home/ga/Fiji_Data/results/morphometry/batch_summary.txt 2>/dev/null || true
rm -f /home/ga/Fiji_Data/results/morphometry/qc_overlay.png 2>/dev/null || true

# Record task start timestamp BEFORE downloading data
echo "Recording task start timestamp..."
date +%s > /tmp/task_start_time
TASK_START=$(cat /tmp/task_start_time)
echo "Task start: $TASK_START"

# Download BBBC008 dataset
echo "Downloading BBBC008 dataset..."
BBBC008_ZIP="/tmp/bbbc008_images.zip"

if [ ! -f "$BBBC008_ZIP" ] || [ ! -s "$BBBC008_ZIP" ]; then
    wget -q --timeout=180 \
        "https://data.broadinstitute.org/bbbc/BBBC008/BBBC008_v1_images.zip" \
        -O "$BBBC008_ZIP" 2>&1
    WGET_STATUS=$?
    if [ $WGET_STATUS -ne 0 ]; then
        echo "WARNING: Download failed (exit $WGET_STATUS). Trying alternate URL..."
        wget -q --timeout=180 \
            "https://bbbc.broadinstitute.org/BBBC008/BBBC008_v1_images.zip" \
            -O "$BBBC008_ZIP" 2>&1 || true
    fi
else
    echo "BBBC008 zip already cached at $BBBC008_ZIP"
fi

# Extract the dataset
if [ -f "$BBBC008_ZIP" ] && [ -s "$BBBC008_ZIP" ]; then
    echo "Extracting BBBC008 images..."
    unzip -q "$BBBC008_ZIP" -d /home/ga/Fiji_Data/raw/bbbc008/ 2>/dev/null || true

    # Count extracted DAPI images
    DAPI_COUNT=$(find /home/ga/Fiji_Data/raw/bbbc008/ -name "*w1*" -o -name "*W1*" 2>/dev/null | wc -l)
    echo "Extracted $DAPI_COUNT DAPI (w1) images"

    # If images are nested in a subdirectory, flatten them
    SUB_DIRS=$(find /home/ga/Fiji_Data/raw/bbbc008/ -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    if [ -n "$SUB_DIRS" ]; then
        echo "Flattening subdirectory structure..."
        for subdir in $SUB_DIRS; do
            mv "$subdir"/* /home/ga/Fiji_Data/raw/bbbc008/ 2>/dev/null || true
            rmdir "$subdir" 2>/dev/null || true
        done
    fi

    echo "Download and extraction complete."
    touch /tmp/bbbc008_download_complete
else
    echo "ERROR: BBBC008 zip file not found or empty."
    echo "ERROR: This task requires the real BBBC008 cell image dataset from Broad Institute."
    echo "ERROR: Please check network connectivity and try again."
    exit 1
fi

# Write scale_info.txt
echo "Writing scale_info.txt..."
cat > /home/ga/Fiji_Data/raw/bbbc008/scale_info.txt << 'SCALEEOF'
# BBBC008 Pixel Scale Information
# Microscope: Nikon TE2000, 40x dry objective, NA 0.75
# Camera: CoolSNAP HQ, 6.45 um pixel size
# Magnification factor: 40x
# Effective pixel size: 6.45 / 40 = 0.16125 um/pixel binned 2x2
# Final scale: 0.3296 um/pixel
scale_um_per_pixel: 0.3296
objective: 40x_dry
SCALEEOF

# Set correct ownership for all files
echo "Setting file ownership..."
chown -R ga:ga /home/ga/Fiji_Data/ 2>/dev/null || true

# Write initial baseline result JSON (0 nuclei - do-nothing baseline)
cat > /tmp/morphometry_result.json << 'JSONEOF'
{
  "task_start": 0,
  "csv_exists": false,
  "csv_modified_after_start": false,
  "total_nuclei": 0,
  "n_images_processed": 0,
  "has_required_columns": false,
  "circularity_all_valid": false,
  "solidity_all_valid": false,
  "area_all_positive": false,
  "summary_exists": false,
  "summary_modified_after_start": false,
  "summary_has_qc_flags": false,
  "summary_size_bytes": 0,
  "overlay_exists": false,
  "overlay_modified_after_start": false,
  "overlay_size_bytes": 0
}
JSONEOF

# Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
FIJI_PID=$!
sleep 10

# Wait for Fiji window to appear
echo "Waiting for Fiji window..."
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "fiji\|imagej" > /dev/null 2>&1; then
        echo "Fiji window detected after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Maximize Fiji window
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/fiji_setup_initial.png 2>/dev/null || true

# List available DAPI images for reference
echo ""
echo "Available DAPI images (w1 channel):"
find /home/ga/Fiji_Data/raw/bbbc008/ -name "*w1*" -o -name "*W1*" 2>/dev/null | sort | head -20
echo ""
echo "Scale info:"
cat /home/ga/Fiji_Data/raw/bbbc008/scale_info.txt

echo ""
echo "=== Setup Complete ==="
echo "BBBC008 DAPI images are at: ~/Fiji_Data/raw/bbbc008/"
echo "Results should be saved to: ~/Fiji_Data/results/morphometry/"
echo "  - nuclear_measurements.csv  (all nucleus measurements)"
echo "  - batch_summary.txt         (per-image summary with PASS/FAIL flags)"
echo "  - qc_overlay.png            (QC overlay for one image)"
