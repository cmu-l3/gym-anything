#!/bin/bash
set -e
echo "=== Setting up intersect_rivers_countries task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 1. Clean up output directory
EXPORTS_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$EXPORTS_DIR"
# Remove any prior output files (shp, shx, dbf, prj, cpg, etc.)
rm -f "$EXPORTS_DIR/rivers_by_country".*
chown -R ga:ga "$EXPORTS_DIR"

# 2. Verify input data exists
COUNTRIES_SHP="/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp"
RIVERS_SHP="/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp"

if [ ! -f "$COUNTRIES_SHP" ] || [ ! -f "$RIVERS_SHP" ]; then
    echo "ERROR: Required input shapefiles not found!"
    exit 1
fi

# 3. Kill any existing gvSIG instances
kill_gvsig

# 4. Launch gvSIG with a fresh state
echo "Launching gvSIG..."
launch_gvsig ""

# 5. Capture initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="