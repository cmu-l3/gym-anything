#!/bin/bash
echo "=== Setting up clean_layer_schema task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous runs
OUTPUT_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/countries_cleaned."* 2>/dev/null || true
echo "Cleaned up previous output files."

# 2. Verify input data exists
check_countries_shapefile || exit 1

# 3. Setup Project
# We copy a clean version of the project file to ensure consistent starting state
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project: $CLEAN_PROJECT"
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# 4. Launch gvSIG
kill_gvsig

if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with project: $PREBUILT_PROJECT"
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "WARNING: Pre-built project not found, launching empty gvSIG..."
    launch_gvsig ""
fi

# 5. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="