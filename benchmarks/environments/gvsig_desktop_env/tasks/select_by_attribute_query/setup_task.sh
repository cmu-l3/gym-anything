#!/bin/bash
echo "=== Setting up select_by_attribute_query task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/gvsig_data/exports
chown ga:ga /home/ga/gvsig_data/exports

# Remove target file if it exists to ensure fresh creation
OUTPUT_FILE="/home/ga/gvsig_data/exports/high_gdp_countries.txt"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing existing output file..."
    rm "$OUTPUT_FILE"
fi

# Verify data availability
check_countries_shapefile || exit 1

# Prepare the project file
# We use the pre-built countries_base project which has the layer loaded
PROJECTS_DIR="/home/ga/gvsig_data/projects"
PREBUILT_PROJECT="$PROJECTS_DIR/countries_base.gvsproj"
SOURCE_PROJECT="/workspace/data/projects/countries_base.gvsproj"

mkdir -p "$PROJECTS_DIR"
if [ -f "$SOURCE_PROJECT" ]; then
    cp "$SOURCE_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    echo "Restored clean project file."
fi

# Kill any existing gvSIG instances
kill_gvsig

# Launch gvSIG with the project
echo "Launching gvSIG..."
launch_gvsig "$PREBUILT_PROJECT"

# Wait for window focus
sleep 2
wmctrl -a "gvSIG" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="