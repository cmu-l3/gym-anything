#!/bin/bash
echo "=== Setting up configure_scale_dependency task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/projects
mkdir -p /home/ga/gvsig_data/cities
chown -R ga:ga /home/ga/gvsig_data

# Verify required data exists
if [ ! -f "/home/ga/gvsig_data/cities/ne_110m_populated_places.shp" ]; then
    echo "ERROR: Populated places shapefile not found!"
    exit 1
fi

# Remove previous result file if it exists
RESULT_PROJECT="/home/ga/gvsig_data/projects/scale_visibility.gvsproj"
if [ -f "$RESULT_PROJECT" ]; then
    rm -f "$RESULT_PROJECT"
    echo "Removed previous result file"
fi

# Reset the base project to a clean state
BASE_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$BASE_PROJECT"
    chown ga:ga "$BASE_PROJECT"
    chmod 644 "$BASE_PROJECT"
    echo "Restored base project"
fi

# Kill any running gvSIG instances
kill_gvsig

# Launch gvSIG with the base project
echo "Launching gvSIG with base project..."
launch_gvsig "$BASE_PROJECT"

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured"

echo "=== Task setup complete ==="