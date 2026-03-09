#!/bin/bash
echo "=== Setting up generate_voronoi_polygons task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Verify Input Data
INPUT_SHP="/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
if [ ! -f "$INPUT_SHP" ]; then
    echo "ERROR: Input shapefile not found at $INPUT_SHP"
    echo "Attempting to locate it..."
    FOUND=$(find /home/ga/gvsig_data -name "ne_110m_populated_places.shp" | head -1)
    if [ -n "$FOUND" ]; then
        echo "Found at $FOUND"
        INPUT_SHP="$FOUND"
        # Create symlink or copy if needed, or just rely on agent finding it?
        # Better to ensure it is where the description says it is.
        mkdir -p /home/ga/gvsig_data/cities
        if [ "$FOUND" != "/home/ga/gvsig_data/cities/ne_110m_populated_places.shp" ]; then
            cp "$FOUND" "/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
            cp "${FOUND%.shp}.shx" "/home/ga/gvsig_data/cities/ne_110m_populated_places.shx" 2>/dev/null || true
            cp "${FOUND%.shp}.dbf" "/home/ga/gvsig_data/cities/ne_110m_populated_places.dbf" 2>/dev/null || true
            cp "${FOUND%.shp}.prj" "/home/ga/gvsig_data/cities/ne_110m_populated_places.prj" 2>/dev/null || true
        fi
    else
        echo "CRITICAL ERROR: Populated places data missing from environment."
        exit 1
    fi
fi

# 3. Clean Output Directory
OUTPUT_DIR="/home/ga/gvsig_data/exports"
OUTPUT_FILE="$OUTPUT_DIR/voronoi_cities.shp"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/voronoi_cities"* 2>/dev/null || true
chown -R ga:ga "$OUTPUT_DIR"
chmod 777 "$OUTPUT_DIR"

# 4. Prepare gvSIG State
# Kill any running instances
kill_gvsig

# Launch gvSIG (clean start)
echo "Launching gvSIG..."
launch_gvsig ""

# 5. Capture Initial State
sleep 2
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup complete ==="
echo "Input: $INPUT_SHP"
echo "Expected Output: $OUTPUT_FILE"