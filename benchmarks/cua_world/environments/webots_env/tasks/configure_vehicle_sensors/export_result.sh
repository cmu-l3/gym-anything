#!/bin/bash
# Export script for configure_vehicle_sensors task
# Checks if the agent saved the configured world and extracts key values.

echo "=== Exporting configure_vehicle_sensors result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/av_sensors_configured.wbt"

FILE_EXISTS="false"
FILE_SIZE=0
CAMERA_WIDTH="not_found"
CAMERA_HEIGHT="not_found"
LIDAR_LAYERS="not_found"
LIDAR_MAXRANGE="not_found"
GPS_PRESENT="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"

    # Extract camera width
    CAMERA_WIDTH=$(grep -oP 'width \K\d+' "$OUTPUT_FILE" | head -1)
    CAMERA_HEIGHT=$(grep -oP 'height \K\d+' "$OUTPUT_FILE" | head -1)

    # Extract lidar fields
    LIDAR_LAYERS=$(grep -oP 'numberOfLayers \K\d+' "$OUTPUT_FILE" | head -1)
    LIDAR_MAXRANGE=$(grep -oP 'maxRange \K[\d.]+' "$OUTPUT_FILE" | head -1)

    # Check GPS presence
    if grep -q "GPS {" "$OUTPUT_FILE"; then
        GPS_PRESENT="true"
    fi

    echo "  Camera: width=$CAMERA_WIDTH, height=$CAMERA_HEIGHT"
    echo "  Lidar: numberOfLayers=$LIDAR_LAYERS, maxRange=$LIDAR_MAXRANGE"
    echo "  GPS present: $GPS_PRESENT"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON
cat > /tmp/configure_vehicle_sensors_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "output_path": "$OUTPUT_FILE",
    "camera_width": "${CAMERA_WIDTH:-not_found}",
    "camera_height": "${CAMERA_HEIGHT:-not_found}",
    "lidar_layers": "${LIDAR_LAYERS:-not_found}",
    "lidar_maxrange": "${LIDAR_MAXRANGE:-not_found}",
    "gps_present": $GPS_PRESENT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/configure_vehicle_sensors_result.json"
cat /tmp/configure_vehicle_sensors_result.json

echo "=== Export Complete ==="
