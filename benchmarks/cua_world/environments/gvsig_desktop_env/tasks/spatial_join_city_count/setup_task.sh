#!/bin/bash
set -e
echo "=== Setting up spatial_join_city_count task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and have correct permissions
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# Verify required input shapefiles exist
echo "Checking input data..."
if ! ls /home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp > /dev/null 2>&1; then
    echo "ERROR: Countries shapefile not found!"
    exit 1
fi

if ! ls /home/ga/gvsig_data/cities/ne_110m_populated_places.shp > /dev/null 2>&1; then
    echo "ERROR: Populated places shapefile not found!"
    exit 1
fi

# Clean up previous outputs to prevent false positives
rm -f /home/ga/gvsig_data/exports/countries_city_count.*
echo "Cleaned up previous output files."

# Kill any existing gvSIG instances
kill_gvsig

# Launch gvSIG with the base countries project
# This ensures the agent starts with the countries layer already loaded
PROJECT_FILE="/home/ga/gvsig_data/projects/countries_base.gvsproj"

if [ -f "$PROJECT_FILE" ]; then
    echo "Launching gvSIG with project: $PROJECT_FILE"
    launch_gvsig "$PROJECT_FILE"
else
    echo "WARNING: Base project not found, launching empty gvSIG"
    launch_gvsig ""
fi

# Take initial screenshot for evidence
sleep 5
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="