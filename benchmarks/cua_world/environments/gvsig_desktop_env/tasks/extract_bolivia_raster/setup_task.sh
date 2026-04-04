#!/bin/bash
set -e
echo "=== Setting up extract_bolivia_raster ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare Directories
mkdir -p /home/ga/gvsig_data/raster
mkdir -p /home/ga/gvsig_data/exports
# Clean previous output
rm -f /home/ga/gvsig_data/exports/bolivia_relief.tif

# 2. Download Natural Earth Raster (Real Data)
# NE1_HR_LC_SR_W_DR.tif is the large 16k x 8k raster
RASTER_URL="https://naturalearth.s3.amazonaws.com/110m_physical/NE1_HR_LC_SR_W_DR.zip"
RASTER_ZIP="/tmp/ne_raster.zip"
RASTER_DEST="/home/ga/gvsig_data/raster/NE1_HR_LC_SR_W_DR.tif"

if [ ! -f "$RASTER_DEST" ]; then
    echo "Downloading Natural Earth Raster..."
    # Use wget with retry
    if wget -q --timeout=120 --tries=3 "$RASTER_URL" -O "$RASTER_ZIP"; then
        unzip -q -o "$RASTER_ZIP" -d "/home/ga/gvsig_data/raster/"
        rm -f "$RASTER_ZIP"
        echo "Raster downloaded and extracted."
    else
        echo "ERROR: Failed to download raster data."
        exit 1
    fi
else
    echo "Raster already exists."
fi

# 3. Ensure Vector Data Exists
check_countries_shapefile || exit 1

# 4. Permissions
chown -R ga:ga /home/ga/gvsig_data

# 5. Launch gvSIG
# We launch with a blank project so the agent has to load layers manually
kill_gvsig
echo "Launching gvSIG..."
launch_gvsig ""

# 6. Capture Initial State
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="