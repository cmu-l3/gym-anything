#!/bin/bash
echo "=== Setting up identify_countries_without_major_rivers task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
EXPORTS_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$EXPORTS_DIR"
rm -f "$EXPORTS_DIR/arid_countries.shp"
rm -f "$EXPORTS_DIR/arid_countries.shx"
rm -f "$EXPORTS_DIR/arid_countries.dbf"
rm -f "$EXPORTS_DIR/arid_countries.prj"

# Verify required input data exists
RIVERS_SHP="/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp"
if [ ! -f "$RIVERS_SHP" ]; then
    echo "ERROR: Rivers shapefile not found at $RIVERS_SHP"
    # Attempt to download if missing (fail-safe)
    echo "Attempting download..."
    wget -q "https://naturalearth.s3.amazonaws.com/110m_physical/ne_110m_rivers_lake_centerlines.zip" -O /tmp/rivers.zip
    unzip -q -o /tmp/rivers.zip -d "/home/ga/gvsig_data/rivers/"
    rm -f /tmp/rivers.zip
fi

# Set permissions
chown -R ga:ga /home/ga/gvsig_data

# Kill any running gvSIG instances
kill_gvsig

# Use the pre-built project that has countries loaded
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Ensure we have a fresh copy of the project
if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Launch gvSIG
if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with base project..."
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "WARNING: Pre-built project not found, launching empty..."
    launch_gvsig ""
fi

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="