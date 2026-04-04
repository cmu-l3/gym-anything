#!/bin/bash
echo "=== Setting up export_bordering_countries task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure export directory exists
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data/exports

# Clean up previous attempts to ensure no stale data
OUTPUT_BASE="/home/ga/gvsig_data/exports/germany_neighbors"
rm -f "${OUTPUT_BASE}.shp" "${OUTPUT_BASE}.shx" "${OUTPUT_BASE}.dbf" "${OUTPUT_BASE}.prj" "${OUTPUT_BASE}.cpg"
echo "Cleaned up previous output files at ${OUTPUT_BASE}.*"

# Verify input data exists
check_countries_shapefile || exit 1

# Kill any running gvSIG instances
kill_gvsig

# Use the pre-built project which has the countries layer loaded
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Restore clean project state
if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project from workspace..."
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Launch gvSIG with the project
if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with project: $PREBUILT_PROJECT"
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "WARNING: Pre-built project not found, launching empty gvSIG..."
    launch_gvsig ""
fi

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved."

echo "=== Task setup complete ==="