#!/bin/bash
echo "=== Setting up select_by_location_export task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/exports
# Clean up previous exports
rm -f /home/ga/gvsig_data/exports/african_cities.*

# Ensure source data exists
check_countries_shapefile || exit 1
if [ ! -f "/home/ga/gvsig_data/cities/ne_110m_populated_places.shp" ]; then
    echo "ERROR: Cities shapefile not found!"
    exit 1
fi

# Install pyshp for the export script validation (running as root during setup)
# We do this here to ensure export_result.sh has the tools it needs
echo "Installing verification dependencies..."
pip3 install pyshp > /dev/null 2>&1 || true

# Kill any running gvSIG
kill_gvsig

# Prepare the project file
PROJECT_DIR="/home/ga/gvsig_data/projects"
mkdir -p "$PROJECT_DIR"
PREBUILT_PROJECT="$PROJECT_DIR/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
    echo "Restored base project: $PREBUILT_PROJECT"
fi

# Launch gvSIG with the project
# Note: The agent will still need to add the cities layer as per description
echo "Launching gvSIG with base project..."
launch_gvsig "$PREBUILT_PROJECT"

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="