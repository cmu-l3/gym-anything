#!/bin/bash
echo "=== Setting up calculate_distance_to_river task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and have correct permissions
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# Clean up previous output to ensure fresh creation
rm -f /home/ga/gvsig_data/exports/cities_river_dist.*

# Verify input data exists
if [ ! -f "/home/ga/gvsig_data/cities/ne_110m_populated_places.shp" ]; then
    echo "ERROR: Cities data missing"
    exit 1
fi
if [ ! -f "/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp" ]; then
    echo "ERROR: Rivers data missing"
    exit 1
fi

# Kill any existing gvSIG instances
kill_gvsig

# Launch gvSIG Desktop (empty, no project loaded)
echo "Launching gvSIG..."
launch_gvsig ""

# Wait for window and maximize
wait_for_window "gvSIG" 60
sleep 2
DISPLAY=:1 wmctrl -r "gvSIG" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="