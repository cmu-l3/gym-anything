#!/bin/bash
echo "=== Setting up extract_asian_leaders_csv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure export directory exists and is writable
mkdir -p /home/ga/gvsig_data/exports
chmod 777 /home/ga/gvsig_data/exports

# Remove any existing output file to ensure fresh creation
OUTPUT_FILE="/home/ga/gvsig_data/exports/asian_leaders.csv"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing previous output file: $OUTPUT_FILE"
    rm -f "$OUTPUT_FILE"
fi

# Verify data availability
if ! check_countries_shapefile; then
    echo "ERROR: Countries shapefile missing!"
    exit 1
fi

# Kill any existing gvSIG instances
kill_gvsig

# Use pre-built project to ensure layer is loaded
# This saves the agent from having to load the layer first
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Restore clean project state
if [ -f "$CLEAN_PROJECT" ]; then
    mkdir -p "$(dirname "$PREBUILT_PROJECT")"
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Launch gvSIG
echo "Launching gvSIG with project: $PREBUILT_PROJECT"
launch_gvsig "$PREBUILT_PROJECT"

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured"

echo "=== Task setup complete ==="