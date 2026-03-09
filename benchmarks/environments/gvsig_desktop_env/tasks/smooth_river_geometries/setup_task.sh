#!/bin/bash
echo "=== Setting up smooth_river_geometries task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Verify Input Data
INPUT_SHP="/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp"
if [ ! -f "$INPUT_SHP" ]; then
    echo "ERROR: Input rivers data not found at $INPUT_SHP"
    # Try to recover by redownloading if needed, or fail
    exit 1
fi
echo "Input data confirmed: $INPUT_SHP"

# Record input file size for later comparison
INPUT_SIZE=$(stat -c %s "$INPUT_SHP")
echo "$INPUT_SIZE" > /tmp/input_size_bytes.txt

# 2. Clean previous outputs
OUTPUT_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/rivers_smooth."*
echo "Cleaned previous output files."

# Ensure permissions
chown -R ga:ga "/home/ga/gvsig_data"

# 3. Launch gvSIG Desktop (Empty State)
# We don't load the project this time, as the task requires loading the layer manually
echo "Launching gvSIG Desktop..."
kill_gvsig
launch_gvsig ""

# 4. Initial Screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="