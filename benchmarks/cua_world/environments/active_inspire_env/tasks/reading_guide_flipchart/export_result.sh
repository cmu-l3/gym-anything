#!/bin/bash
# Export script for Reading Guide Flipchart task
# Extracts verification data from the agent's created flipchart.

echo "=== Exporting Reading Guide Flipchart Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

FILE_PATH="/home/ga/Documents/Flipcharts/charlottes_web_guide.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/charlottes_web_guide.flp"

FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

HAS_CHARLOTTE="false"
HAS_WILBUR="false"
HAS_FERN="false"
HAS_COMPREHENSION="false"
HAS_THEME="false"

RECT_COUNT=0
CIRCLE_COUNT=0
TOTAL_SHAPE_COUNT=0

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

    if check_flipchart_file "$ACTUAL_PATH"; then
        FILE_VALID="true"
    fi

    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then

        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        if echo "$ALL_TEXT" | grep -qi "Charlotte"; then
            HAS_CHARLOTTE="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Wilbur"; then
            HAS_WILBUR="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "\bFern\b"; then
            HAS_FERN="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Comprehension\|Questions"; then
            HAS_COMPREHENSION="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Theme\|Message\|Lesson"; then
            HAS_THEME="true"
        fi

        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII"; then
                R=$(grep -ic 'AsRectangle\|shapeType="Rectangle"\|type="Rectangle"' "$XML_FILE" 2>/dev/null || echo 0)
                C=$(grep -ic 'AsCircle\|AsEllipse\|AsOval\|type="Circle"\|type="Ellipse"' "$XML_FILE" 2>/dev/null || echo 0)
                S=$(grep -ic 'AsShape' "$XML_FILE" 2>/dev/null || echo 0)
                RECT_COUNT=$((RECT_COUNT + R))
                CIRCLE_COUNT=$((CIRCLE_COUNT + C))
                TOTAL_SHAPE_COUNT=$((TOTAL_SHAPE_COUNT + S))
            fi
        done
    fi
    rm -rf "$TMP_DIR"
fi

python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_valid": '$FILE_VALID' == 'true',
    "page_count": $PAGE_COUNT,
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "has_charlotte": '$HAS_CHARLOTTE' == 'true',
    "has_wilbur": '$HAS_WILBUR' == 'true',
    "has_fern": '$HAS_FERN' == 'true',
    "has_comprehension": '$HAS_COMPREHENSION' == 'true',
    "has_theme": '$HAS_THEME' == 'true',
    "rect_count": $RECT_COUNT,
    "circle_count": $CIRCLE_COUNT,
    "total_shape_count": $TOTAL_SHAPE_COUNT,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON written successfully")
PYEOF

if [ ! -f /tmp/task_result.json ]; then
    cat > /tmp/task_result.json << EOF
{
    "file_found": $FILE_FOUND,
    "file_valid": $FILE_VALID,
    "page_count": $PAGE_COUNT,
    "created_during_task": $CREATED_DURING_TASK,
    "has_charlotte": $HAS_CHARLOTTE,
    "has_wilbur": $HAS_WILBUR,
    "has_fern": $HAS_FERN,
    "has_comprehension": $HAS_COMPREHENSION,
    "has_theme": $HAS_THEME,
    "rect_count": $RECT_COUNT
}
EOF
fi

chmod 666 /tmp/task_result.json
echo "Result: $(cat /tmp/task_result.json)"
echo "=== Export Complete ==="
