#!/bin/bash
set -e
echo "=== Setting up Repair and Reproject task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Prepare directories
BROKEN_DIR="/home/ga/gvsig_data/projects/broken_data"
EXPORT_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$BROKEN_DIR"
mkdir -p "$EXPORT_DIR"

# 2. Prepare Source Data (Real Data)
# We use the Natural Earth populated places shapefile available in the environment
SOURCE_SHP="/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"

if [ ! -f "$SOURCE_SHP" ]; then
    echo "ERROR: Source data ne_110m_populated_places.shp not found!"
    # Fallback to download if missing (should not happen in this env)
    exit 1
fi

echo "Creating 'broken' dataset from $SOURCE_SHP..."

# Copy all shapefile components (.shp, .shx, .dbf, etc.)
cp "/home/ga/gvsig_data/cities/ne_110m_populated_places."* "$BROKEN_DIR/"

# Rename files to 'cities_missing_prj'
for f in "$BROKEN_DIR"/ne_110m_populated_places.*; do
    extension="${f##*.}"
    mv "$f" "$BROKEN_DIR/cities_missing_prj.$extension"
done

# CRITICAL STEP: Delete the .prj file to create the "missing projection" scenario
rm -f "$BROKEN_DIR/cities_missing_prj.prj"

echo "Broken dataset created at: $BROKEN_DIR/cities_missing_prj.shp"

# 3. Clean up previous results
rm -f "$EXPORT_DIR/cities_web_mercator."*

# 4. Set permissions
chown -R ga:ga "/home/ga/gvsig_data"

# 5. Launch gvSIG
# We launch without a project file so the agent starts fresh
echo "Launching gvSIG..."
kill_gvsig
launch_gvsig ""

# 6. Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="