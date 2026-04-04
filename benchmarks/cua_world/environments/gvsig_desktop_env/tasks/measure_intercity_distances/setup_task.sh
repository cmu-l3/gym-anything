#!/bin/bash
echo "=== Setting up measure_intercity_distances task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# Clean up previous output
rm -f /home/ga/gvsig_data/exports/distances.txt

# Check required data
check_countries_shapefile || exit 1
CITIES_SHP="/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
if [ ! -f "$CITIES_SHP" ]; then
    echo "ERROR: Cities shapefile not found at $CITIES_SHP"
    exit 1
fi

# Kill any running gvSIG
kill_gvsig

# Use the pre-built countries project
# We do NOT pre-load the cities layer; the agent must do that as part of the task
# to ensure they know how to manage layers and find data.
PROJECT_FILE="/home/ga/gvsig_data/projects/countries_base.gvsproj"
PREBUILT_SOURCE="/workspace/data/projects/countries_base.gvsproj"

# Ensure clean project state
if [ -f "$PREBUILT_SOURCE" ]; then
    cp "$PREBUILT_SOURCE" "$PROJECT_FILE"
    chown ga:ga "$PROJECT_FILE"
fi

# Launch gvSIG
echo "Launching gvSIG with countries project..."
launch_gvsig "$PROJECT_FILE"

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="