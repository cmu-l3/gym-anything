#!/bin/bash
echo "=== Exporting generate_riparian_zones_union result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Define expected paths
BUFFER_SHP="/home/ga/gvsig_data/exports/river_buffers.shp"
UNION_SHP="/home/ga/gvsig_data/exports/countries_rivers_union.shp"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check Buffer File
BUFFER_EXISTS="false"
BUFFER_SIZE="0"
BUFFER_NEW="false"
if [ -f "$BUFFER_SHP" ]; then
    BUFFER_EXISTS="true"
    BUFFER_SIZE=$(stat -c %s "$BUFFER_SHP")
    BUFFER_MTIME=$(stat -c %Y "$BUFFER_SHP")
    if [ "$BUFFER_MTIME" -gt "$TASK_START" ]; then
        BUFFER_NEW="true"
    fi
    # Copy for verification
    cp "$BUFFER_SHP" /tmp/river_buffers.shp
    cp "${BUFFER_SHP%.*}.dbf" /tmp/river_buffers.dbf 2>/dev/null || true
    cp "${BUFFER_SHP%.*}.shx" /tmp/river_buffers.shx 2>/dev/null || true
fi

# Check Union File
UNION_EXISTS="false"
UNION_SIZE="0"
UNION_NEW="false"
if [ -f "$UNION_SHP" ]; then
    UNION_EXISTS="true"
    UNION_SIZE=$(stat -c %s "$UNION_SHP")
    UNION_MTIME=$(stat -c %Y "$UNION_SHP")
    if [ "$UNION_MTIME" -gt "$TASK_START" ]; then
        UNION_NEW="true"
    fi
    # Copy for verification
    cp "$UNION_SHP" /tmp/countries_rivers_union.shp
    cp "${UNION_SHP%.*}.dbf" /tmp/countries_rivers_union.dbf 2>/dev/null || true
    cp "${UNION_SHP%.*}.shx" /tmp/countries_rivers_union.shx 2>/dev/null || true
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "buffer_exists": $BUFFER_EXISTS,
    "buffer_created_during_task": $BUFFER_NEW,
    "buffer_size": $BUFFER_SIZE,
    "union_exists": $UNION_EXISTS,
    "union_created_during_task": $UNION_NEW,
    "union_size": $UNION_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json
chmod 666 /tmp/*.shp /tmp/*.dbf /tmp/*.shx 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"