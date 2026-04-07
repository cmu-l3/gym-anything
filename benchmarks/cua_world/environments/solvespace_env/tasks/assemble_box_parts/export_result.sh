#!/bin/bash
echo "=== Exporting assemble_box_parts task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ASSEMBLY_FILE="/home/ga/Documents/SolveSpace/box_assembly.slvs"

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
IS_VALID_FORMAT="false"
LINKED_GROUP_COUNT="0"
REFERENCES_BASE="false"
REFERENCES_SIDE="false"
ENTITY_COUNT="0"

# Check the file properties and parse for required indicators
if [ -f "$ASSEMBLY_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$ASSEMBLY_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$ASSEMBLY_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check format (looks for standard SolveSpace headers/groups)
    if head -n 10 "$ASSEMBLY_FILE" | grep -qi "solvespace\|Group\.\|AddGroup"; then
        IS_VALID_FORMAT="true"
    fi
    
    # Count linked groups (SolveSpace uses Group.type=5300 for linked/assembled groups)
    LINKED_GROUP_COUNT=$(grep -c "Group\.type=5300" "$ASSEMBLY_FILE" 2>/dev/null || echo "0")
    
    # Check for references to the target part files
    if grep -qi "base\.slvs" "$ASSEMBLY_FILE" 2>/dev/null; then
        REFERENCES_BASE="true"
    fi
    if grep -qi "side\.slvs" "$ASSEMBLY_FILE" 2>/dev/null; then
        REFERENCES_SIDE="true"
    fi
    
    # Count entities to ensure the file actually has imported geometry
    ENTITY_COUNT=$(grep -c "^AddEntity" "$ASSEMBLY_FILE" 2>/dev/null || echo "0")
fi

APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Create JSON result safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "is_valid_format": $IS_VALID_FORMAT,
    "linked_group_count": $LINKED_GROUP_COUNT,
    "references_base_slvs": $REFERENCES_BASE,
    "references_side_slvs": $REFERENCES_SIDE,
    "entity_count": $ENTITY_COUNT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location safely (handle permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="