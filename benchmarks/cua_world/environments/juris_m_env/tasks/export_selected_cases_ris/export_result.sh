#!/bin/bash
echo "=== Exporting export_selected_cases_ris results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Output file path
OUTPUT_FILE="/home/ga/Documents/landmark_cases.ris"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
RIS_VALID="false"
ITEM_COUNT=0
CONTAINS_BROWN="false"
CONTAINS_MIRANDA="false"
CONTAINS_GIDEON="false"
CONTAINS_UNWANTED="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")

    # Check creation time
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check if valid RIS (look for TY tags)
    if grep -q "^TY  -" "$OUTPUT_FILE"; then
        RIS_VALID="true"
        # Count items (ER tag marks end of record in RIS)
        ITEM_COUNT=$(grep -c "^ER  -" "$OUTPUT_FILE" || echo "0")
    fi

    # Check for specific content (case insensitive)
    if grep -qi "Brown v\. Board" "$OUTPUT_FILE" || grep -qi "Brown v Board" "$OUTPUT_FILE"; then
        CONTAINS_BROWN="true"
    fi
    if grep -qi "Miranda v\. Arizona" "$OUTPUT_FILE" || grep -qi "Miranda v Arizona" "$OUTPUT_FILE"; then
        CONTAINS_MIRANDA="true"
    fi
    if grep -qi "Gideon v\. Wainwright" "$OUTPUT_FILE" || grep -qi "Gideon v Wainwright" "$OUTPUT_FILE"; then
        CONTAINS_GIDEON="true"
    fi

    # Check for unwanted items to detect "Export Collection" instead of "Export Items"
    # (Checking for other common cases in the injected set)
    if grep -qi "Marbury" "$OUTPUT_FILE" || grep -qi "Obergefell" "$OUTPUT_FILE" || grep -qi "Tinker" "$OUTPUT_FILE"; then
        CONTAINS_UNWANTED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "ris_valid": $RIS_VALID,
    "item_count": $ITEM_COUNT,
    "contains_brown": $CONTAINS_BROWN,
    "contains_miranda": $CONTAINS_MIRANDA,
    "contains_gideon": $CONTAINS_GIDEON,
    "contains_unwanted": $CONTAINS_UNWANTED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="