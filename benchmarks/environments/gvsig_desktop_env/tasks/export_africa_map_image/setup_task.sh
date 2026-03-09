#!/bin/bash
set -e
echo "=== Setting up export_africa_map_image task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the exports directory exists and is clean
EXPORTS_DIR="/home/ga/gvsig_data/exports"
rm -rf "$EXPORTS_DIR"
mkdir -p "$EXPORTS_DIR"
chown -R ga:ga "$EXPORTS_DIR"

# Verify all required Natural Earth datasets are present
echo "Checking Natural Earth data files..."
MISSING_DATA=0
for dataset in \
    "/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp" \
    "/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp" \
    "/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"; do
    if [ ! -f "$dataset" ]; then
        echo "ERROR: Missing required data file: $dataset"
        MISSING_DATA=1
    else
        echo "  OK: $dataset"
    fi
done

if [ "$MISSING_DATA" -eq 1 ]; then
    echo "Attempting to re-download missing data..."
    # Fallback: run install script data download function if needed
    # (Assuming data is usually baked into the image, but being robust)
    exit 1
fi

# Kill any existing gvSIG instances
kill_gvsig

# Launch gvSIG with a fresh session (no project file loaded)
# Passing empty string to launch_gvsig ensures no project is loaded
launch_gvsig ""

# Give gvSIG time to fully initialize
sleep 10

# Maximize the gvSIG window to ensure good visibility for the agent
# Using task_utils helper or direct wmctrl
if ! DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null; then
    # Fallback to finding by name
    DISPLAY=:1 wmctrl -r "gvSIG" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="