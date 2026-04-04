#!/bin/bash
echo "=== Exporting apply_team_patch result ==="

source /workspace/scripts/task_utils.sh

# Define paths
WORKSPACE="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE/RadiationTherapy"
SRC_DIR="$PROJECT_DIR/src/main/java/com/med/physics"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Read file contents
CALC_CONTENT=""
CONST_CONTENT=""
CALC_MODIFIED="false"
CONST_MODIFIED="false"

if [ -f "$SRC_DIR/DoseCalculator.java" ]; then
    CALC_CONTENT=$(cat "$SRC_DIR/DoseCalculator.java" 2>/dev/null)
    CALC_MTIME=$(stat -c %Y "$SRC_DIR/DoseCalculator.java" 2>/dev/null || echo "0")
    if [ "$CALC_MTIME" -gt "$TASK_START" ]; then
        CALC_MODIFIED="true"
    fi
fi

if [ -f "$SRC_DIR/CalibrationConstants.java" ]; then
    CONST_CONTENT=$(cat "$SRC_DIR/CalibrationConstants.java" 2>/dev/null)
    CONST_MTIME=$(stat -c %Y "$SRC_DIR/CalibrationConstants.java" 2>/dev/null || echo "0")
    if [ "$CONST_MTIME" -gt "$TASK_START" ]; then
        CONST_MODIFIED="true"
    fi
fi

# Check for compilation state (presence of class files)
COMPILED="false"
if [ -f "$PROJECT_DIR/target/classes/com/med/physics/DoseCalculator.class" ]; then
    COMPILED="true"
fi

# Escape content for JSON
CALC_ESCAPED=$(echo "$CALC_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
CONST_ESCAPED=$(echo "$CONST_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create result JSON
RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "calc_modified": $CALC_MODIFIED,
    "const_modified": $CONST_MODIFIED,
    "calc_content": $CALC_ESCAPED,
    "const_content": $CONST_ESCAPED,
    "compiled": $COMPILED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="