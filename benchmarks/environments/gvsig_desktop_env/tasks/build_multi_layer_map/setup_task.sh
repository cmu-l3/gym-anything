#!/bin/bash
set -e
echo "=== Setting up build_multi_layer_map task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Verify source data exists
echo "Checking data files..."
MISSING_DATA=0
for dataset in "countries/ne_110m_admin_0_countries" "rivers/ne_110m_rivers_lake_centerlines" "cities/ne_110m_populated_places"; do
    shp="/home/ga/gvsig_data/${dataset}.shp"
    if [ ! -f "$shp" ]; then
        echo "ERROR: Missing shapefile: $shp"
        MISSING_DATA=1
    else
        echo "  OK: $shp"
    fi
done

if [ "$MISSING_DATA" -eq 1 ]; then
    echo "CRITICAL: Required data missing. Task cannot proceed."
    exit 1
fi

# Clean up any previous task artifacts
OUTPUT_PROJECT="/home/ga/gvsig_data/projects/reference_map.gvsproj"
rm -f "$OUTPUT_PROJECT" 2>/dev/null || true

# Ensure exports directory exists and is writable
mkdir -p /home/ga/gvsig_data/projects
chown -R ga:ga /home/ga/gvsig_data

# Kill any existing gvSIG instances
kill_gvsig

# Launch gvSIG fresh (no project file -> opens Project Manager)
echo "Launching gvSIG Desktop..."
# We use empty string to launch without loading a specific project
launch_gvsig ""

# Wait extra time for full initialization and window focus
sleep 5

# Attempt to maximize the window to ensure VLM has a good view
WID=$(DISPLAY=:1 wmctrl -l | grep -i "gvSIG" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent should see gvSIG Project Manager window."
echo "Data files available at /home/ga/gvsig_data/"