#!/bin/bash
# Export script for Classroom Schedule Flipchart task
# Extracts verification data from the agent's created flipchart.

echo "=== Exporting Classroom Schedule Flipchart Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

FILE_PATH="/home/ga/Documents/Flipcharts/daily_schedule.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/daily_schedule.flp"

FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

HAS_SCHEDULE="false"
HAS_MORNING_MEETING="false"
HAS_READING="false"
HAS_MATH="false"
HAS_SCIENCE="false"
HAS_LUNCH="false"
HAS_HOMEWORK="false"

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

        if echo "$ALL_TEXT" | grep -qi "Schedule\|Agenda"; then
            HAS_SCHEDULE="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Morning Meeting\|Morning\|Meeting"; then
            HAS_MORNING_MEETING="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "\bReading\b\|Reading Workshop"; then
            HAS_READING="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "\bMath\b"; then
            HAS_MATH="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "\bScience\b"; then
            HAS_SCIENCE="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "\bLunch\b"; then
            HAS_LUNCH="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Homework\|Home Work"; then
            HAS_HOMEWORK="true"
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
    "has_schedule": '$HAS_SCHEDULE' == 'true',
    "has_morning_meeting": '$HAS_MORNING_MEETING' == 'true',
    "has_reading": '$HAS_READING' == 'true',
    "has_math": '$HAS_MATH' == 'true',
    "has_science": '$HAS_SCIENCE' == 'true',
    "has_lunch": '$HAS_LUNCH' == 'true',
    "has_homework": '$HAS_HOMEWORK' == 'true',
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
    "has_schedule": $HAS_SCHEDULE,
    "has_morning_meeting": $HAS_MORNING_MEETING,
    "has_reading": $HAS_READING,
    "has_math": $HAS_MATH,
    "has_science": $HAS_SCIENCE,
    "has_lunch": $HAS_LUNCH,
    "has_homework": $HAS_HOMEWORK,
    "rect_count": $RECT_COUNT
}
EOF
fi

chmod 666 /tmp/task_result.json
echo "Result: $(cat /tmp/task_result.json)"
echo "=== Export Complete ==="
