#!/bin/bash
echo "=== Setting up convert_vector_to_raster task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Define output path
OUTPUT_DIR="/home/ga/gvsig_data/exports"
OUTPUT_FILE="$OUTPUT_DIR/country_grid.tif"

# Ensure output directory exists and is writable
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"
chmod 755 "$OUTPUT_DIR"

# Clean up previous output to ensure we verify a NEW file
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing previous output file: $OUTPUT_FILE"
    rm -f "$OUTPUT_FILE"
fi

# Verify input data exists
check_countries_shapefile || exit 1

# Kill any running gvSIG instances
kill_gvsig

# -------------------------------------------------------------------
# Launch gvSIG with the base project containing countries layer
# -------------------------------------------------------------------
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Restore clean project state
if [ -f "$CLEAN_PROJECT" ]; then
    mkdir -p "$(dirname "$PREBUILT_PROJECT")"
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

echo "Launching gvSIG with project: $PREBUILT_PROJECT"
launch_gvsig "$PREBUILT_PROJECT"

# Take initial screenshot for evidence
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="