#!/bin/bash
echo "=== Setting up generate_weighted_city_buffers task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and are clean
mkdir -p /home/ga/gvsig_data/exports
rm -f /home/ga/gvsig_data/exports/city_influence.* 2>/dev/null || true

# Check input data
if [ ! -f "/home/ga/gvsig_data/cities/ne_110m_populated_places.shp" ]; then
    echo "ERROR: Input cities shapefile not found!"
    exit 1
fi

# Ensure permissions
chown -R ga:ga /home/ga/gvsig_data

# Kill any running gvSIG instances
kill_gvsig

# Use the countries base project as a starting point (provides CRS and context)
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project: $CLEAN_PROJECT"
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Launch gvSIG with the base project
echo "Launching gvSIG with countries basemap..."
if [ -f "$PREBUILT_PROJECT" ]; then
    launch_gvsig "$PREBUILT_PROJECT"
else
    launch_gvsig ""
fi

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_start.png
echo "Initial screenshot saved to /tmp/task_start.png"

echo "=== Task setup complete ==="