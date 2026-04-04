#!/bin/bash
echo "=== Setting up generate_remote_areas_difference task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/exports
mkdir -p /home/ga/gvsig_data/projects
chown -R ga:ga /home/ga/gvsig_data

# Clean up previous outputs
rm -f /home/ga/gvsig_data/exports/remote_areas.*

# Verify required input data exists
check_countries_shapefile || exit 1
CITIES_SHP="/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
if [ ! -f "$CITIES_SHP" ]; then
    echo "ERROR: Populated places shapefile not found at $CITIES_SHP"
    exit 1
fi

# Kill any running gvSIG instances
kill_gvsig

# Use pre-built project which has countries loaded
# We rely on the agent to load the cities layer as part of the task workflow
# (simulating a common workflow where one adds data to an existing base map)
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

echo "Launching gvSIG with countries project..."
if [ -f "$PREBUILT_PROJECT" ]; then
    launch_gvsig "$PREBUILT_PROJECT"
else
    # Fallback to empty project if prebuilt missing
    launch_gvsig ""
fi

# Maximize the window (launch_gvsig handles wait, but we ensure max here)
sleep 2
DISPLAY=:1 wmctrl -r "gvSIG" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="