#!/bin/bash
echo "=== Exporting Fire Drill Evacuation Map Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/fire_evacuation_plan.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/fire_evacuation_plan.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Content analysis variables
HAS_TITLE_TEXT="false"
HAS_TEACHER_TEXT="false"
HAS_EXIT_TEXT="false"
SHAPE_COUNT=0
ARROW_COUNT=0

# Check primary path, then alt
if [ -f "$FILE_PATH" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH"
elif [ -f "$FILE_PATH_ALT" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH_ALT"
fi

if [ "$FILE_FOUND" = "true" ]; then
    FILE_SIZE=$(get_file_size "$ACTUAL_PATH")
    FILE_MTIME=$(get_file_mtime "$ACTUAL_PATH")

    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check timestamp
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Analyze content
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # 1. Text Analysis
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE")"
            fi
        done

        if echo "$ALL_TEXT" | grep -qiE "Fire|Evacuation|Drill"; then
            HAS_TITLE_TEXT="true"
        fi
        if echo "$ALL_TEXT" | grep -qiE "Teacher|Desk"; then
            HAS_TEACHER_TEXT="true"
        fi
        if echo "$ALL_TEXT" | grep -qiE "Door|Exit"; then
            HAS_EXIT_TEXT="true"
        fi

        # 2. Shape & Arrow Analysis
        # Count shape elements in all XML files
        # Shapes: AsRectangle, AsCircle, AsShape, etc.
        # Arrows: AsArrow, AsConnector, or lines
        
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Count general shapes (Rects, Circles, Shapes)
            S=$(grep -icE 'AsRectangle|AsCircle|AsShape|AsSquare|type="Rectangle"|type="Circle"' "$XML_FILE" 2>/dev/null || echo 0)
            SHAPE_COUNT=$((SHAPE_COUNT + S))

            # Count arrows/connectors
            # ActivInspire often uses AsArrow or AsConnector for lines/arrows
            A=$(grep -icE 'AsArrow|AsConnector|startArrow|endArrow' "$XML_FILE" 2>/dev/null || echo 0)
            ARROW_COUNT=$((ARROW_COUNT + A))
        done
    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON result
# Using python for safe JSON generation
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_valid": '$FILE_VALID' == 'true',
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "has_title_text": '$HAS_TITLE_TEXT' == 'true',
    "has_teacher_text": '$HAS_TEACHER_TEXT' == 'true',
    "has_exit_text": '$HAS_EXIT_TEXT' == 'true',
    "shape_count": $SHAPE_COUNT,
    "arrow_count": $ARROW_COUNT,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="