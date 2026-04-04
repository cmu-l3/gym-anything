#!/bin/bash
echo "=== Setting up calculate_true_areas task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ensure input data exists
check_countries_shapefile || exit 1

# Ensure export directory exists and is empty of previous results
mkdir -p /home/ga/gvsig_data/exports
rm -f /home/ga/gvsig_data/exports/countries_area.*
chown -R ga:ga /home/ga/gvsig_data/exports

# Clean up any running gvSIG instances
kill_gvsig

# Launch gvSIG with an empty project (no arguments)
# The agent must load the data themselves as per description
echo "Launching gvSIG Desktop..."
launch_gvsig ""

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="
echo "Task: Calculate True Country Areas"
echo "Input: /home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp"
echo "Output: /home/ga/gvsig_data/exports/countries_area.shp"