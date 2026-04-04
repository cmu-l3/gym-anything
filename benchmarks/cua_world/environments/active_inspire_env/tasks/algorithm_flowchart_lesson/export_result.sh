#!/bin/bash
# Export script for Algorithm Flowchart Lesson task

echo "=== Exporting Algorithm Flowchart Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot of the state
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Define expected paths
FILE_PATH="/home/ga/Documents/Flipcharts/algorithm_flowchart.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/algorithm_flowchart.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"

# Text content flags
HAS_SYMBOLS_TITLE="false"
HAS_START_LABEL="false"
HAS_PROCESS_LABEL="false"
HAS_DECISION_LABEL="false"
HAS_MORNING_TITLE="false"
HAS_ALARM_TEXT="false"
HAS_WEEKDAY_TEXT="false"
HAS_SLEEP_TEXT="false"

# Shape counts
RECT_COUNT=0
OVAL_COUNT=0
DIAMOND_COUNT=0
LINE_COUNT=0
TOTAL_SHAPE_COUNT=0

# Check if file exists
if [ -f "$FILE_PATH" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH"
elif [ -f "$FILE_PATH_ALT" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH_ALT"
fi

# Analyze file if found
if [ "$FILE_FOUND" = "true" ]; then
    FILE_SIZE=$(get_file_size "$ACTUAL_PATH")
    FILE_MTIME=$(get_file_mtime "$ACTUAL_PATH")
    
    # Check validity (zip/xml structure)
    if check_flipchart_file "$ACTUAL_PATH"; then
        FILE_VALID="true"
    fi

    # Timestamp check
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Content Analysis (Unzip and grep XML)
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # 1. Text Analysis
        # Concatenate all text-like files to search for strings
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Basic check if it's an XML file
            if head -n 1 "$XML_FILE" | grep -q "xml"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE")"
            fi
        done

        # Check for required text terms (case-insensitive)
        if echo "$ALL_TEXT" | grep -qi "Symbols"; then HAS_SYMBOLS_TITLE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Start"; then HAS_START_LABEL="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Process"; then HAS_PROCESS_LABEL="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Decision"; then HAS_DECISION_LABEL="true"; fi
        
        if echo "$ALL_TEXT" | grep -qi "Morning"; then HAS_MORNING_TITLE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Alarm"; then HAS_ALARM_TEXT="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Weekday"; then HAS_WEEKDAY_TEXT="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Sleep"; then HAS_SLEEP_TEXT="true"; fi

        # 2. Shape Analysis
        # Iterate XML files to count shape tags
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            
            # Rectangles
            R=$(grep -icE 'AsRectangle|shapeType="Rectangle"|type="Rectangle"' "$XML_FILE" || echo 0)
            RECT_COUNT=$((RECT_COUNT + R))
            
            # Ovals/Ellipses
            O=$(grep -icE 'AsEllipse|AsCircle|AsOval|type="Ellipse"|type="Circle"' "$XML_FILE" || echo 0)
            OVAL_COUNT=$((OVAL_COUNT + O))
            
            # Diamonds/Decisions (often polygons or specific shapes in Inspire)
            # Checking for 'Diamond', 'Rhombus', or generic 'AsPolygon' which implies custom shapes
            D=$(grep -icE 'shapeType="Diamond"|type="Diamond"|AsPolygon' "$XML_FILE" || echo 0)
            DIAMOND_COUNT=$((DIAMOND_COUNT + D))

            # Lines/Connectors
            L=$(grep -icE 'AsLine|AsConnector|type="Line"|type="Connector"' "$XML_FILE" || echo 0)
            LINE_COUNT=$((LINE_COUNT + L))
            
            # Total Shapes (generic count)
            S=$(grep -icE 'AsShape|AsLine|AsConnector' "$XML_FILE" || echo 0)
            TOTAL_SHAPE_COUNT=$((TOTAL_SHAPE_COUNT + S))
        done
    fi
    rm -rf "$TMP_DIR"
fi

# Write result to JSON using Python for safety
python3 << PYEOF
import json
import os

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_valid": '$FILE_VALID' == 'true',
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "page_count": $PAGE_COUNT,
    "text_analysis": {
        "has_symbols": '$HAS_SYMBOLS_TITLE' == 'true',
        "has_start": '$HAS_START_LABEL' == 'true',
        "has_process": '$HAS_PROCESS_LABEL' == 'true',
        "has_decision": '$HAS_DECISION_LABEL' == 'true',
        "has_morning": '$HAS_MORNING_TITLE' == 'true',
        "has_alarm": '$HAS_ALARM_TEXT' == 'true',
        "has_weekday": '$HAS_WEEKDAY_TEXT' == 'true',
        "has_sleep": '$HAS_SLEEP_TEXT' == 'true'
    },
    "shape_analysis": {
        "rect_count": $RECT_COUNT,
        "oval_count": $OVAL_COUNT,
        "diamond_count": $DIAMOND_COUNT,
        "line_count": $LINE_COUNT,
        "total_shape_count": $TOTAL_SHAPE_COUNT
    },
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="