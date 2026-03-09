#!/bin/bash
# Export script for Water Cycle Flipchart task
# Extracts verification data from the agent's created flipchart.

echo "=== Exporting Water Cycle Flipchart Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

FILE_PATH="/home/ga/Documents/Flipcharts/water_cycle_lesson.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/water_cycle_lesson.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Text content flags
HAS_WATER_CYCLE="false"
HAS_EVAPORATION="false"
HAS_CONDENSATION="false"
HAS_PRECIPITATION="false"
HAS_QUICK_CHECK="false"

# Shape counts
RECT_COUNT=0
CIRCLE_COUNT=0
TOTAL_SHAPE_COUNT=0

# Check for file
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

        if echo "$ALL_TEXT" | grep -qi "Water Cycle\|WaterCycle"; then
            HAS_WATER_CYCLE="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Evaporation\|Evaporate"; then
            HAS_EVAPORATION="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Condensation\|Condense"; then
            HAS_CONDENSATION="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Precipitation\|Precipitate"; then
            HAS_PRECIPITATION="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Quick Check\|Quick\|Assessment\|Review"; then
            HAS_QUICK_CHECK="true"
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
    "has_water_cycle": '$HAS_WATER_CYCLE' == 'true',
    "has_evaporation": '$HAS_EVAPORATION' == 'true',
    "has_condensation": '$HAS_CONDENSATION' == 'true',
    "has_precipitation": '$HAS_PRECIPITATION' == 'true',
    "has_quick_check": '$HAS_QUICK_CHECK' == 'true',
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
    "has_water_cycle": $HAS_WATER_CYCLE,
    "has_evaporation": $HAS_EVAPORATION,
    "has_condensation": $HAS_CONDENSATION,
    "has_precipitation": $HAS_PRECIPITATION,
    "has_quick_check": $HAS_QUICK_CHECK,
    "total_shape_count": $TOTAL_SHAPE_COUNT
}
EOF
fi

chmod 666 /tmp/task_result.json
echo "Result: $(cat /tmp/task_result.json)"
echo "=== Export Complete ==="
