#!/bin/bash
echo "=== Exporting Fire Alarm Markup Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_entity_count.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/LibreCAD/floorplan_fire_alarm.dxf"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check basic file stats
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Run Internal DXF Analysis (using ezdxf inside container)
# We capture the JSON output from the python script
DXF_ANALYSIS="{}"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    DXF_ANALYSIS=$(python3 /usr/local/bin/verify_fire_alarm_dxf.py "$OUTPUT_FILE")
fi

# 4. Construct Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "initial_entity_count": $INITIAL_COUNT,
    "dxf_analysis": $DXF_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="