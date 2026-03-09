#!/bin/bash
echo "=== Setting up add_xy_coordinates task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state
# Remove the output file if it exists from a previous run
OUTPUT_DIR="/home/ga/gvsig_data/exports"
rm -f "$OUTPUT_DIR/cities_with_coords.shp"
rm -f "$OUTPUT_DIR/cities_with_coords.shx"
rm -f "$OUTPUT_DIR/cities_with_coords.dbf"
rm -f "$OUTPUT_DIR/cities_with_coords.prj"
rm -f "$OUTPUT_DIR/cities_with_coords.qpj"
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR"

# Ensure input data exists
INPUT_FILE="/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: Input file $INPUT_FILE not found!"
    # Try to re-download or fail
    exit 1
fi
echo "Input file confirmed: $INPUT_FILE"

# 3. Launch gvSIG
# We launch a fresh instance to ensure no stray dialogs
kill_gvsig

echo "Launching gvSIG..."
launch_gvsig ""

# 4. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="