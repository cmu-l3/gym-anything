#!/bin/bash
echo "=== Setting up calculate_city_density_on_grid task ==="

source /workspace/scripts/task_utils.sh

# 1. Verify input data exists
CITIES_SHP="/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
if [ ! -f "$CITIES_SHP" ]; then
    echo "ERROR: Cities shapefile not found at $CITIES_SHP"
    exit 1
fi
echo "Input data verified: $CITIES_SHP"

# 2. Clean up previous run artifacts
OUTPUT_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/city_density_grid."* 2>/dev/null || true
echo "Cleaned up previous exports"

# 3. Ensure permissions
chown -R ga:ga "$OUTPUT_DIR"
chown -R ga:ga "/home/ga/gvsig_data/cities"

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch gvSIG Desktop (fresh start)
kill_gvsig
echo "Launching gvSIG..."
launch_gvsig ""

# 6. Take initial screenshot
sleep 5
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Create 20x20 degree grid and count cities per cell"
echo "Input: $CITIES_SHP"
echo "Output: $OUTPUT_DIR/city_density_grid.shp"