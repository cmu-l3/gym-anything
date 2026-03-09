#!/bin/bash
echo "=== Setting up convex_hull_cities task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous outputs
EXPORT_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/convex_hull_cities"*
echo "Cleaned previous exports in $EXPORT_DIR"

# 2. Verify input data exists
INPUT_FILE="/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: Input file not found at $INPUT_FILE"
    # Try to copy from backup if available, or just fail
    exit 1
fi
echo "Input data verified: $INPUT_FILE"

# 3. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch gvSIG
# We start with a fresh session to ensure no UI clutter
kill_gvsig
launch_gvsig ""

# 5. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="