#!/bin/bash
set -e
echo "=== Setting up export_layer_to_kml task ==="

source /workspace/scripts/task_utils.sh

# 1. Anti-gaming: Record start time
date +%s > /tmp/task_start_time.txt

# 2. Clean state: Remove any previous export
EXPORT_FILE="/home/ga/gvsig_data/exports/world_countries.kml"
rm -f "$EXPORT_FILE"
mkdir -p /home/ga/gvsig_data/exports
chown ga:ga /home/ga/gvsig_data/exports

# 3. Ensure gvSIG is running with the correct project
# We use the pre-built project which has the countries layer loaded and styled
PROJECT_FILE="/home/ga/gvsig_data/projects/countries_base.gvsproj"
PREBUILT_SOURCE="/workspace/data/projects/countries_base.gvsproj"

# Restore clean project file if available
if [ -f "$PREBUILT_SOURCE" ]; then
    cp "$PREBUILT_SOURCE" "$PROJECT_FILE"
    chown ga:ga "$PROJECT_FILE"
fi

# Kill any existing instances to ensure clean start
kill_gvsig

# Launch gvSIG
if [ -f "$PROJECT_FILE" ]; then
    echo "Launching gvSIG with project: $PROJECT_FILE"
    launch_gvsig "$PROJECT_FILE"
else
    echo "WARNING: Project file not found, launching empty gvSIG"
    launch_gvsig ""
fi

# 4. Final prep
# Wait a moment for UI to settle
sleep 5
# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="