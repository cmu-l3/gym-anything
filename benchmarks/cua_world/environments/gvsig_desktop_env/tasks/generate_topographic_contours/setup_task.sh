#!/bin/bash
echo "=== Setting up generate_topographic_contours task ==="

source /workspace/scripts/task_utils.sh

# Directory setup
mkdir -p /home/ga/gvsig_data/raster
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# 1. Prepare Data (Helsinki DEM)
DEM_PATH="/home/ga/gvsig_data/raster/Helsinki_DEM.tif"
DEM_URL="https://github.com/Automating-GIS-processes/CSC18/raw/master/data/Helsinki_DEM_2x2m_Subset.tif"

if [ ! -f "$DEM_PATH" ]; then
    echo "Downloading Helsinki DEM..."
    if wget -q --timeout=60 "$DEM_URL" -O "$DEM_PATH"; then
        echo "Download successful."
    else
        echo "ERROR: Download failed. Creating dummy DEM for fallback (not ideal for verification)."
        # Create a synthetic DEM if download fails (fallback to prevent task crash, though verification might fail)
        convert -size 512x512 gradient:black-white -depth 16 "$DEM_PATH" 2>/dev/null || true
    fi
fi
chown ga:ga "$DEM_PATH"

# 2. Clean previous outputs
rm -f /home/ga/gvsig_data/exports/helsinki_contours.* 2>/dev/null || true

# 3. Launch gvSIG (Clean state)
kill_gvsig
echo "Launching gvSIG..."
launch_gvsig ""

# 4. Record start time
date +%s > /tmp/task_start_time.txt

# 5. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Input Data: $DEM_PATH"
echo "Target Output: /home/ga/gvsig_data/exports/helsinki_contours.shp"