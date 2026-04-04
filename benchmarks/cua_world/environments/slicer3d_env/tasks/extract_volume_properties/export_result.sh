#!/bin/bash
echo "=== Exporting Extract Volume Properties Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check expected output file
OUTPUT_PATH="/home/ga/Documents/SlicerData/Exports/volume_properties.json"

OUTPUT_EXISTS="false"
OUTPUT_VALID_JSON="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"
OUTPUT_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Try to read and validate JSON
    OUTPUT_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null || echo "")
    if python3 -c "import json; json.loads('''$OUTPUT_CONTENT''')" 2>/dev/null; then
        OUTPUT_VALID_JSON="true"
    fi
    
    echo "Output file found: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $(date -d @$OUTPUT_MTIME 2>/dev/null || echo $OUTPUT_MTIME)"
    echo "  Created during task: $FILE_CREATED_DURING_TASK"
    echo "  Valid JSON: $OUTPUT_VALID_JSON"
    echo "  Content:"
    cat "$OUTPUT_PATH" 2>/dev/null || true
else
    echo "Output file NOT found at $OUTPUT_PATH"
    
    # Search for any volume_properties.json file
    echo "Searching for alternative locations..."
    FOUND_FILES=$(find /home/ga -name "volume_properties.json" -o -name "*properties*.json" 2>/dev/null | head -5)
    if [ -n "$FOUND_FILES" ]; then
        echo "Found possible output files:"
        echo "$FOUND_FILES"
        # Use first found file
        ALT_PATH=$(echo "$FOUND_FILES" | head -1)
        if [ -f "$ALT_PATH" ]; then
            echo "Using: $ALT_PATH"
            OUTPUT_CONTENT=$(cat "$ALT_PATH" 2>/dev/null || echo "")
            OUTPUT_EXISTS="true"
            OUTPUT_SIZE=$(stat -c %s "$ALT_PATH" 2>/dev/null || echo "0")
            OUTPUT_MTIME=$(stat -c %Y "$ALT_PATH" 2>/dev/null || echo "0")
            if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
                FILE_CREATED_DURING_TASK="true"
            fi
            if python3 -c "import json; json.loads('''$OUTPUT_CONTENT''')" 2>/dev/null; then
                OUTPUT_VALID_JSON="true"
            fi
        fi
    fi
fi

# Parse output JSON to extract values
REPORTED_VOLUME_NAME=""
REPORTED_DIMENSIONS=""
REPORTED_SPACING=""
REPORTED_SCALAR_TYPE=""
REPORTED_NUM_COMPONENTS=""

if [ "$OUTPUT_VALID_JSON" = "true" ] && [ -n "$OUTPUT_CONTENT" ]; then
    REPORTED_VOLUME_NAME=$(python3 -c "import json; d=json.loads('''$OUTPUT_CONTENT'''); print(d.get('volume_name', ''))" 2>/dev/null || echo "")
    REPORTED_DIMENSIONS=$(python3 -c "import json; d=json.loads('''$OUTPUT_CONTENT'''); print(json.dumps(d.get('dimensions', [])))" 2>/dev/null || echo "[]")
    REPORTED_SPACING=$(python3 -c "import json; d=json.loads('''$OUTPUT_CONTENT'''); print(json.dumps(d.get('spacing_mm', [])))" 2>/dev/null || echo "[]")
    REPORTED_SCALAR_TYPE=$(python3 -c "import json; d=json.loads('''$OUTPUT_CONTENT'''); print(d.get('scalar_type', ''))" 2>/dev/null || echo "")
    REPORTED_NUM_COMPONENTS=$(python3 -c "import json; d=json.loads('''$OUTPUT_CONTENT'''); print(d.get('num_components', 0))" 2>/dev/null || echo "0")
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Check what module Slicer is showing (if possible via window title)
CURRENT_MODULE=""
SLICER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1 | cut -d' ' -f5-)
if echo "$SLICER_TITLE" | grep -qi "volumes"; then
    CURRENT_MODULE="Volumes"
fi

# Get ground truth for comparison
GT_PATH="/var/lib/slicer/ground_truth/mrhead_properties.json"
GT_DIMENSIONS=""
GT_SPACING=""
GT_SCALAR_TYPE=""
GT_NUM_COMPONENTS=""

if [ -f "$GT_PATH" ]; then
    GT_DIMENSIONS=$(python3 -c "import json; print(json.dumps(json.load(open('$GT_PATH')).get('dimensions', [])))" 2>/dev/null || echo "[]")
    GT_SPACING=$(python3 -c "import json; print(json.dumps(json.load(open('$GT_PATH')).get('spacing_mm', [])))" 2>/dev/null || echo "[]")
    GT_SCALAR_TYPE=$(python3 -c "import json; print(json.load(open('$GT_PATH')).get('scalar_type', ''))" 2>/dev/null || echo "")
    GT_NUM_COMPONENTS=$(python3 -c "import json; print(json.load(open('$GT_PATH')).get('num_components', 1))" 2>/dev/null || echo "1")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_valid_json": $OUTPUT_VALID_JSON,
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "slicer_was_running": $SLICER_RUNNING,
    "current_module": "$CURRENT_MODULE",
    "reported_volume_name": "$REPORTED_VOLUME_NAME",
    "reported_dimensions": $REPORTED_DIMENSIONS,
    "reported_spacing": $REPORTED_SPACING,
    "reported_scalar_type": "$REPORTED_SCALAR_TYPE",
    "reported_num_components": $REPORTED_NUM_COMPONENTS,
    "gt_dimensions": $GT_DIMENSIONS,
    "gt_spacing": $GT_SPACING,
    "gt_scalar_type": "$GT_SCALAR_TYPE",
    "gt_num_components": $GT_NUM_COMPONENTS,
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/volume_properties_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/volume_properties_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/volume_properties_task_result.json
chmod 666 /tmp/volume_properties_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/volume_properties_task_result.json
echo ""
echo "=== Export Complete ==="