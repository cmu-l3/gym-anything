#!/bin/bash
echo "=== Setting up open_vector_layer task ==="

source /workspace/scripts/task_utils.sh

# Verify data exists
check_countries_shapefile || exit 1

# Show the exact path the agent needs to navigate to
SHP_PATH=$(ls /home/ga/gvsig_data/countries/*.shp 2>/dev/null | head -1)
echo "Countries shapefile to load: $SHP_PATH"

# Ensure projects directory is writable
mkdir -p /home/ga/gvsig_data/projects
chown -R ga:ga /home/ga/gvsig_data

# Kill any running gvSIG
kill_gvsig

# Launch gvSIG with empty project (no file argument)
echo "Launching gvSIG..."
launch_gvsig ""

# Take initial screenshot for verification
sleep 3
take_screenshot /tmp/task_start.png
echo "Initial screenshot saved to /tmp/task_start.png"

echo "=== Task setup complete ==="
echo "Task: Load $SHP_PATH as a vector layer in a new gvSIG View"
