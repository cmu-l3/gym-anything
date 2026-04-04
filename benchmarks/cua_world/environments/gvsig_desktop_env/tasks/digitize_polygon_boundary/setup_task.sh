#!/bin/bash
echo "=== Setting up digitize_polygon_boundary task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/projects
chown -R ga:ga /home/ga/gvsig_data

# Clean up any previous attempts to ensure a fresh start
rm -f /home/ga/gvsig_data/projects/iceland_boundary.*
echo "Cleaned up previous task artifacts."

# Verify reference data exists
if [ ! -f "/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp" ]; then
    echo "ERROR: Reference countries shapefile not found!"
    # Try to re-download or fail
    exit 1
fi

# Kill any running gvSIG instances
kill_gvsig

# Launch gvSIG with an empty state (no project loaded)
# The agent must load the reference layer themselves as part of the task
echo "Launching gvSIG Desktop..."
launch_gvsig ""

# Wait for window to settle
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="