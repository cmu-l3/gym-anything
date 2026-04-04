#!/bin/bash
echo "=== Setting up summarize_gdp_by_continent task ==="

source /workspace/scripts/task_utils.sh

# Verify data exists
check_countries_shapefile || exit 1

# Ensure exports directory exists and is writable
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data/exports

# Remove any previous output file
OUTPUT_CSV="/home/ga/gvsig_data/exports/continent_gdp_summary.csv"
if [ -f "$OUTPUT_CSV" ]; then
    echo "Removing previous output file: $OUTPUT_CSV"
    rm "$OUTPUT_CSV"
fi

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Kill any running gvSIG
kill_gvsig

# Use pre-built project which has the countries layer already loaded
# This saves the agent from having to find and load the layer manually,
# allowing them to focus on the analysis part.
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Ensure the project file is fresh
if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Launch gvSIG
if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with project: $PREBUILT_PROJECT"
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "Launching fresh gvSIG (project not found)..."
    launch_gvsig ""
fi

# Wait for window and maximize
wait_for_window "gvSIG" 60
sleep 2
# Ensure it is maximized
DISPLAY=:1 wmctrl -r "gvSIG" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="