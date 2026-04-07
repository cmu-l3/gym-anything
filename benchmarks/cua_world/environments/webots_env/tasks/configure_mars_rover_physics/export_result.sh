#!/bin/bash
echo "=== Exporting configure_mars_rover_physics result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/mars_rover.wbt"

FILE_EXISTS="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write basic metadata to JSON. We let the python verifier do the deep regex
# parsing of the .wbt file using copy_from_env to avoid bash string parsing complexities.
cat > /tmp/mars_rover_physics_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "output_path": "$OUTPUT_FILE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/mars_rover_physics_result.json"
cat /tmp/mars_rover_physics_result.json

echo "=== Export Complete ==="