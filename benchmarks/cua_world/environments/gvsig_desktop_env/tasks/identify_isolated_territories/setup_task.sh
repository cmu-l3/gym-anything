#!/bin/bash
echo "=== Setting up Identify Isolated Territories Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and have permissions
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# Clean up previous run artifacts to ensure fresh creation
OUTPUT_BASE="/home/ga/gvsig_data/exports/isolated_territories"
rm -f "${OUTPUT_BASE}.shp" "${OUTPUT_BASE}.shx" "${OUTPUT_BASE}.dbf" "${OUTPUT_BASE}.prj" 2>/dev/null || true

# Check source data
check_countries_shapefile || exit 1
CITIES_SHP="/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
if [ ! -f "$CITIES_SHP" ]; then
    echo "ERROR: Cities shapefile not found at $CITIES_SHP"
    exit 1
fi

# Kill any running gvSIG instances
kill_gvsig

# Launch gvSIG with a fresh/empty state
# We do NOT load a project file because the task requires loading layers manually
echo "Launching gvSIG..."
launch_gvsig ""

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved."

echo "=== Task setup complete ==="
echo "Data locations:"
echo " - Countries: /home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp"
echo " - Cities:    /home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
echo "Target Output: /home/ga/gvsig_data/exports/isolated_territories.shp"