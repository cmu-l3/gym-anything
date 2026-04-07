#!/bin/bash
echo "=== Exporting HL7 Fragment Aggregator result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_channel_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_channel_count)
OUTPUT_DIR="/home/ga/aggregated_output"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check output files
FILE_COUNT=$(ls -1 "$OUTPUT_DIR"/*.hl7 2>/dev/null | wc -l)
OUTPUT_FILE=""
OUTPUT_CONTENT=""
OBX_COUNT=0
FILE_CREATED_TIME=0

if [ "$FILE_COUNT" -gt 0 ]; then
    # Get the most recently modified file
    OUTPUT_FILE=$(ls -t "$OUTPUT_DIR"/*.hl7 | head -1)
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE")
    FILE_CREATED_TIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Count OBX segments in the output file
    OBX_COUNT=$(grep -c "^OBX|" "$OUTPUT_FILE")
fi

# Check if file was created during task
CREATED_DURING_TASK="false"
if [ "$FILE_CREATED_TIME" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Determine if the correct channel exists
CHANNEL_EXISTS="false"
CHANNEL_ID=""
CHANNEL_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%aggregator%' OR LOWER(name) LIKE '%lipid%';" 2>/dev/null || true)

if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f1)
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_channel_count": $INITIAL_COUNT,
    "current_channel_count": $CURRENT_COUNT,
    "channel_exists": $CHANNEL_EXISTS,
    "output_file_count": $FILE_COUNT,
    "obx_segment_count": $OBX_COUNT,
    "file_created_during_task": $CREATED_DURING_TASK,
    "output_content_preview": "$(echo "$OUTPUT_CONTENT" | head -n 20 | sed 's/"/\\"/g' | tr '\n' ' ')"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json