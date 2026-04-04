#!/bin/bash
echo "=== Setting up identify_cities_on_major_rivers task ==="

source /workspace/scripts/task_utils.sh

# Install pyshp for validation script in export_result.sh
echo "Installing dependencies for validation..."
pip3 install pyshp > /dev/null 2>&1 || true

# Clean previous outputs
rm -f /home/ga/gvsig_data/exports/river_cities.*
mkdir -p /home/ga/gvsig_data/exports/
chown -R ga:ga /home/ga/gvsig_data/exports/

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch gvSIG with an empty project
echo "Launching gvSIG..."
kill_gvsig
launch_gvsig ""

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved."

echo "=== Setup complete ==="