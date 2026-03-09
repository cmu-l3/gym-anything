#!/bin/bash
echo "=== Exporting debug_infinite_loop_dose result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

PROJECT_ROOT="/home/ga/eclipse-workspace/RayPlan"
OUTPUT_FILE="/home/ga/Desktop/dose_report.csv"
SRC_FILE="$PROJECT_ROOT/src/main/java/com/rayplan/math/GradientDescentOptimizer.java"

# 1. Check if output file exists and when it was modified
OUTPUT_EXISTS="false"
OUTPUT_TIMESTAMP=0
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_TIMESTAMP=$(stat -c %Y "$OUTPUT_FILE")
fi

# 2. Capture the output file content for verification
OUTPUT_CONTENT=""
if [ "$OUTPUT_EXISTS" = "true" ]; then
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE")
fi

# 3. Capture the source code for verification (to check for the fix)
SRC_CONTENT=""
if [ -f "$SRC_FILE" ]; then
    SRC_CONTENT=$(cat "$SRC_FILE")
fi

# 4. Check if Eclipse was used (Debug history)
DEBUG_USED="false"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
DEBUG_UI_DIR="$WORKSPACE_DIR/.metadata/.plugins/org.eclipse.debug.ui"
if [ -d "$DEBUG_UI_DIR" ]; then
    if [ -f "$DEBUG_UI_DIR/launchConfigurationHistory.xml" ]; then
        DEBUG_USED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# We use python to dump json to avoid quoting issues with file content
python3 -c "
import json
import os

data = {
    'task_start': $TASK_START,
    'output_exists': $OUTPUT_EXISTS == 'true',
    'output_timestamp': $OUTPUT_TIMESTAMP,
    'debug_used': $DEBUG_USED == 'true',
    'output_content': '''$OUTPUT_CONTENT''',
    'src_content': '''$SRC_CONTENT'''
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="