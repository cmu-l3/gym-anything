#!/bin/bash
echo "=== Setting up Identify Flood-Safe Cities Task ==="

source /workspace/scripts/task_utils.sh

# Install GDAL tools for verification (if not present)
if ! command -v ogrinfo &> /dev/null; then
    echo "Installing gdal-bin for verification tools..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq gdal-bin > /dev/null
fi

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# Clean up previous run artifacts
rm -f /home/ga/gvsig_data/exports/river_buffer_05deg.* 2>/dev/null
rm -f /home/ga/gvsig_data/exports/safe_cities.* 2>/dev/null

# Verify source data exists
echo "Verifying source data..."
check_countries_shapefile || exit 1
if [ ! -f "/home/ga/gvsig_data/cities/ne_110m_populated_places.shp" ]; then
    echo "ERROR: Cities data missing"
    exit 1
fi
if [ ! -f "/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp" ]; then
    echo "ERROR: Rivers data missing"
    exit 1
fi

# Kill any running gvSIG
kill_gvsig

# Re-copy the clean pre-built project
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project from workspace: $CLEAN_PROJECT"
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch gvSIG
if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with base project..."
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "Base project not found, launching empty..."
    launch_gvsig ""
fi

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_start.png
echo "Initial screenshot saved to /tmp/task_start.png"

echo "=== Task setup complete ==="