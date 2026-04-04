#!/bin/bash
# Export script for Student Certificate Template task

echo "=== Exporting Student Certificate Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/student_certificate.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/student_certificate.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Content flags
HAS_TITLE="false"
HAS_AWARDED="false"
HAS_DATE="false"
HAS_SIGNED="false"

# Shape counts
RECT_COUNT=0
LINE_COUNT=0
STAR_CIRCLE_COUNT=0
TOTAL_SHAPE_COUNT=0

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

    # Validate flipchart format
    if check_flipchart_file "$ACTUAL_PATH"; then
        FILE_VALID="true"
    fi

    # Check creation time vs task start
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Extract content for analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then

        # Collect text from all XML files
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Basic text extraction
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # --- Text checks ---
        if echo "$ALL_TEXT" | grep -qi "Student of the Month"; then
            HAS_TITLE="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Awarded to\|Awarded"; then
            HAS_AWARDED="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Date:"; then
            HAS_DATE="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Signed:\|Teacher:"; then
            HAS_SIGNED="true"
        fi

        # --- Shape analysis ---
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII"; then
                # Count rectangles (Border)
                R=$(grep -ic 'AsRectangle\|shapeType="Rectangle"\|type="Rectangle"' "$XML_FILE" 2>/dev/null || echo 0)
                RECT_COUNT=$((RECT_COUNT + R))

                # Count lines (Form fields)
                L=$(grep -ic 'AsLine\|shapeType="Line"\|type="Line"' "$XML_FILE" 2>/dev/null || echo 0)
                LINE_COUNT=$((LINE_COUNT + L))

                # Count decorations (Stars, Circles, etc)
                SC=$(grep -ic 'AsStar\|AsCircle\|AsEllipse\|shapeType="Star"\|shapeType="Circle"' "$XML_FILE" 2>/dev/null || echo 0)
                STAR_CIRCLE_COUNT=$((STAR_CIRCLE_COUNT + SC))

                # Total generic shapes if specific tags fail
                S=$(grep -ic 'AsShape' "$XML_FILE" 2>/dev/null || echo 0)
                TOTAL_SHAPE_COUNT=$((TOTAL_SHAPE_COUNT + S))
            fi
        done
    fi
    rm -rf "$TMP_DIR"
fi

# Create result JSON using Python for safety
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_valid": '$FILE_VALID' == 'true',
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "has_title": '$HAS_TITLE' == 'true',
    "has_awarded": '$HAS_AWARDED' == 'true',
    "has_date": '$HAS_DATE' == 'true',
    "has_signed": '$HAS_SIGNED' == 'true',
    "rect_count": $RECT_COUNT,
    "line_count": $LINE_COUNT,
    "star_circle_count": $STAR_CIRCLE_COUNT,
    "total_shape_count": $TOTAL_SHAPE_COUNT,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON written successfully")
PYEOF

chmod 666 /tmp/task_result.json
echo "Result: $(cat /tmp/task_result.json)"
echo "=== Export Complete ==="