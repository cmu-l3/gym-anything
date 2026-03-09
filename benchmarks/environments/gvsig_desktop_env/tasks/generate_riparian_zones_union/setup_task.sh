#!/bin/bash
echo "=== Setting up generate_riparian_zones_union task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# Clean up any previous run artifacts
rm -f /home/ga/gvsig_data/exports/river_buffers.*
rm -f /home/ga/gvsig_data/exports/countries_rivers_union.*

# Verify source data exists
RIVERS_SHP="/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp"
if [ ! -f "$RIVERS_SHP" ]; then
    echo "ERROR: Rivers shapefile not found at $RIVERS_SHP"
    exit 1
fi
echo "Rivers shapefile verified at $RIVERS_SHP"

check_countries_shapefile || exit 1

# Kill any running gvSIG
kill_gvsig

# Use pre-built project with countries loaded
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project from workspace"
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

echo "Launching gvSIG with countries project..."
if [ -f "$PREBUILT_PROJECT" ]; then
    launch_gvsig "$PREBUILT_PROJECT"
else
    # Fallback to empty launch if project missing
    echo "WARNING: Pre-built project not found, launching empty"
    launch_gvsig ""
fi

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="