#!/bin/bash
set -e
echo "=== Setting up generate_vector_grid_overlay task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
OUTPUT_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/australia_grid."*
chown -R ga:ga "$OUTPUT_DIR"

# Verify input data exists
check_countries_shapefile || exit 1

# Kill any running gvSIG instances
kill_gvsig

# Use pre-built project which has countries layer loaded
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Ensure we have a fresh copy of the project
if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

echo "Launching gvSIG with project: $PREBUILT_PROJECT"
launch_gvsig "$PREBUILT_PROJECT"

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved"

echo "=== Task setup complete ==="