#!/bin/bash
echo "=== Setting up reproject_layer_to_mercator task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare data directories
DATA_DIR="/home/ga/gvsig_data"
EXPORT_DIR="$DATA_DIR/exports"
PROJECTS_DIR="$DATA_DIR/projects"

# Ensure directories exist and are writable
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "$DATA_DIR"
chmod -R 755 "$DATA_DIR"

# 2. Clean up previous artifacts to ensure fresh run
TARGET_FILE="$EXPORT_DIR/countries_mercator.shp"
rm -f "$EXPORT_DIR/countries_mercator."* 2>/dev/null || true
echo "Cleaned up old export: $TARGET_FILE"

# 3. Setup the Project File
# Use the base project that has the countries layer pre-loaded
PREBUILT_PROJECT="$PROJECTS_DIR/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Restore clean project state
if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
    echo "Restored base project"
fi

# 4. Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded"

# 5. Launch gvSIG
# Kill any existing instances first
kill_gvsig

if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with project: $PREBUILT_PROJECT"
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "WARNING: Prebuilt project not found, launching empty gvSIG"
    launch_gvsig ""
fi

# 6. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured"

echo "=== Task setup complete ==="