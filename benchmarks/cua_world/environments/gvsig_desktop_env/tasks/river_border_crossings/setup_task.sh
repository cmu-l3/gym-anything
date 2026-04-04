#!/bin/bash
echo "=== Setting up river_border_crossings task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# Clean up any previous output
rm -f /home/ga/gvsig_data/exports/river_crossings.*

# Check if input data exists
if [ ! -f "/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp" ] || \
   [ ! -f "/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp" ]; then
    echo "ERROR: Required input data missing!"
    exit 1
fi

# Kill any running gvSIG instances
kill_gvsig

# Launch gvSIG with an empty project (agent must load data)
echo "Launching gvSIG..."
launch_gvsig ""

# Wait for window and maximize
wait_for_window "gvSIG" 60
WID=$(wmctrl -l | grep -i "gvSIG" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="