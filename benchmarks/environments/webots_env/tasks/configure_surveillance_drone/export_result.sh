#!/bin/bash
# Export script for configure_surveillance_drone task
# Checks if the agent saved the configured drone world and extracts key values.

echo "=== Exporting configure_surveillance_drone result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/surveillance_drone.wbt"

FILE_EXISTS="false"
FILE_SIZE=0
CAMERA_WIDTH="not_found"
CAMERA_HEIGHT="not_found"
CAMERA_FOV="not_found"
GPS_PRESENT="false"
DRONE_ALTITUDE="not_found"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"

    # Extract camera parameters
    CAMERA_WIDTH=$(grep -oP 'width \K\d+' "$OUTPUT_FILE" | head -1)
    CAMERA_HEIGHT=$(grep -oP 'height \K\d+' "$OUTPUT_FILE" | head -1)
    CAMERA_FOV=$(grep -oP 'fieldOfView \K[\d.]+' "$OUTPUT_FILE" | head -1)

    # Check GPS presence
    if grep -q "GPS {" "$OUTPUT_FILE"; then
        GPS_PRESENT="true"
    fi

    # Extract drone altitude (Z component of SURVEILLANCE_DRONE translation)
    DRONE_ALTITUDE=$(python3 -c "
import re
with open('$OUTPUT_FILE') as f:
    content = f.read()

# Find SURVEILLANCE_DRONE and get its translation Z
idx = content.find('SURVEILLANCE_DRONE')
if idx == -1:
    # Fall back: find any Robot translation
    idx = content.find('DEF ')

if idx != -1:
    segment = content[idx:idx+500]
    m = re.search(r'translation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', segment)
    if m:
        print(m.group(3))
    else:
        print('not_found')
else:
    print('not_found')
" 2>/dev/null || echo "not_found")

    echo "  Camera: width=$CAMERA_WIDTH, height=$CAMERA_HEIGHT, FOV=$CAMERA_FOV"
    echo "  GPS present: $GPS_PRESENT"
    echo "  Drone altitude (Z): $DRONE_ALTITUDE"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON
cat > /tmp/configure_surveillance_drone_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "output_path": "$OUTPUT_FILE",
    "camera_width": "${CAMERA_WIDTH:-not_found}",
    "camera_height": "${CAMERA_HEIGHT:-not_found}",
    "camera_fov": "${CAMERA_FOV:-not_found}",
    "gps_present": $GPS_PRESENT,
    "drone_altitude": "${DRONE_ALTITUDE:-not_found}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/configure_surveillance_drone_result.json"
cat /tmp/configure_surveillance_drone_result.json

echo "=== Export Complete ==="
