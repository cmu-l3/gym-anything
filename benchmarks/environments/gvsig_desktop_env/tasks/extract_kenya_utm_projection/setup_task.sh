#!/bin/bash
echo "=== Setting up extract_kenya_utm_projection task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
rm -f /home/ga/gvsig_data/exports/kenya_utm.* 2>/dev/null || true
mkdir -p /home/ga/gvsig_data/exports/
chown -R ga:ga /home/ga/gvsig_data/exports/

# Verify input data exists
check_countries_shapefile || exit 1

# Kill any running gvSIG
kill_gvsig

# Use the pre-built project which has countries layer loaded
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Ensure we have a clean project file
if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with project: $PREBUILT_PROJECT"
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "Launching fresh gvSIG..."
    launch_gvsig ""
fi

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="
echo "Target: Select Kenya and export to /home/ga/gvsig_data/exports/kenya_utm.shp"
echo "Target CRS: EPSG:32737"