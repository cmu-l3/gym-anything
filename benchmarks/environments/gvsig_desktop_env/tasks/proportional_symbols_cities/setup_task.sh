#!/bin/bash
echo "=== Setting up proportional_symbols_cities task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/projects
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# Clean up previous artifacts
rm -f /home/ga/gvsig_data/projects/proportional_cities.gvsproj
rm -f /home/ga/gvsig_data/exports/proportional_cities.png

# Verify source data exists
if [ ! -f "/home/ga/gvsig_data/cities/ne_110m_populated_places.shp" ]; then
    echo "ERROR: Populated places shapefile not found!"
    # Try to copy from backup if available or fail
    exit 1
fi

# Kill any running gvSIG instances
kill_gvsig

# Launch gvSIG with the base countries project
# This gives the agent the background layer but requires them to add the cities layer
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with base project..."
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "Launching empty gvSIG..."
    launch_gvsig ""
fi

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured"

echo "=== Task setup complete ==="