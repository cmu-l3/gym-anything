#!/bin/bash
echo "=== Setting up extract_vertices_south_america task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
EXPORTS_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$EXPORTS_DIR"
rm -f "$EXPORTS_DIR/sa_vertices.shp" "$EXPORTS_DIR/sa_vertices.shx" "$EXPORTS_DIR/sa_vertices.dbf" "$EXPORTS_DIR/sa_vertices.prj"

# Ensure permissions
chown -R ga:ga "/home/ga/gvsig_data"

# Kill any running gvSIG instances
kill_gvsig

# Use the pre-built project which has the countries layer loaded
# This saves the agent from having to find/load the layer first
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Reset project file to clean state
if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Launch gvSIG with the project
echo "Launching gvSIG with countries project..."
launch_gvsig "$PREBUILT_PROJECT"

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured"

echo "=== Task setup complete ==="