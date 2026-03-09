#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/AutoVer"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the shared launch file exists
LAUNCH_FILE="$PROJECT_DIR/VersionGenerator.launch"
LAUNCH_EXISTS="false"
LAUNCH_CONTENT=""

if [ -f "$LAUNCH_FILE" ]; then
    LAUNCH_EXISTS="true"
    LAUNCH_CONTENT=$(cat "$LAUNCH_FILE")
fi

# 2. Check if the output file exists and was created AFTER task start
OUTPUT_FILE="$PROJECT_DIR/src/main/resources/version.txt"
OUTPUT_EXISTS="false"
OUTPUT_FRESH="false"
OUTPUT_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE")
    
    # Get file modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        OUTPUT_FRESH="true"
    fi
fi

# 3. Check .project file for builder configuration
PROJECT_FILE="$PROJECT_DIR/.project"
PROJECT_CONTENT=""
if [ -f "$PROJECT_FILE" ]; then
    PROJECT_CONTENT=$(cat "$PROJECT_FILE")
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare JSON result
# Use python to escape strings safely
PYTHON_SCRIPT=$(cat <<EOF
import json
import sys

data = {
    "launch_exists": $LAUNCH_EXISTS,
    "output_exists": $OUTPUT_EXISTS,
    "output_fresh": $OUTPUT_FRESH,
    "launch_content": """$LAUNCH_CONTENT""",
    "project_content": """$PROJECT_CONTENT""",
    "output_content": """$OUTPUT_CONTENT""",
    "timestamp": "$(date -Iseconds)"
}
print(json.dumps(data))
EOF
)

# Write JSON using python
python3 -c "$PYTHON_SCRIPT" > /tmp/temp_result.json

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm /tmp/temp_result.json

echo "Results exported to /tmp/task_result.json"