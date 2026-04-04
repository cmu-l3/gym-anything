#!/bin/bash
set -e
echo "=== Setting up Reproject View CRS Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous task artifacts
OUTPUT_PROJECT="/home/ga/gvsig_data/projects/mercator_project.gvsproj"
rm -f "$OUTPUT_PROJECT"
rm -f /tmp/task_initial_state.png
rm -f /tmp/task_result.json

# 2. Ensure exports directory exists and is writable
mkdir -p /home/ga/gvsig_data/projects
chown -R ga:ga /home/ga/gvsig_data

# 3. Ensure the base project exists
BASE_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
SOURCE_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ ! -f "$BASE_PROJECT" ]; then
    echo "Base project not found at $BASE_PROJECT"
    if [ -f "$SOURCE_PROJECT" ]; then
        echo "Restoring from workspace data..."
        cp "$SOURCE_PROJECT" "$BASE_PROJECT"
        chown ga:ga "$BASE_PROJECT"
    else
        echo "ERROR: Source project not found! Cannot set up task."
        exit 1
    fi
fi

# 4. Check countries shapefile exists (required by the project)
check_countries_shapefile || exit 1

# 5. Store a hash of the base project for comparison during verification
md5sum "$BASE_PROJECT" 2>/dev/null | awk '{print $1}' > /tmp/base_project_hash.txt

# 6. Launch gvSIG with the base project
# This uses the shared utility to handle Java environment and window waiting
launch_gvsig "$BASE_PROJECT"

# 7. Final window checks
echo "Ensuring gvSIG is focused and maximized..."
# Wait a moment for window manager to register the window fully
sleep 2
DISPLAY=:1 wmctrl -a "gvSIG" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="