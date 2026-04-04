#!/bin/bash
# Export script for Lesson Opener Flipchart task
# Extracts verification data from the agent's created flipchart.

echo "=== Exporting Lesson Opener Flipchart Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/american_revolution_opener.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/american_revolution_opener.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_TYPE="unknown"
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Text content flags
HAS_DO_NOW="false"
HAS_OBJECTIVES="false"
HAS_VOCABULARY="false"
HAS_REVOLUTION="false"
HAS_COLONY="false"
HAS_INDEPENDENCE="false"
HAS_PATRIOT="false"

# Shape counts
RECT_COUNT=0
CIRCLE_COUNT=0
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
    FILE_TYPE=$(file -b "$ACTUAL_PATH" 2>/dev/null | head -c 100 | tr '"' "'" || echo "unknown")

    # Validate flipchart format
    if check_flipchart_file "$ACTUAL_PATH"; then
        FILE_VALID="true"
    fi

    # Check creation time vs task start
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract content for text and shape analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then

        # Collect text from all XML files
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # --- Text content checks ---
        if echo "$ALL_TEXT" | grep -qi "Do Now"; then
            HAS_DO_NOW="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Objective"; then
            HAS_OBJECTIVES="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Vocabulary\|Vocab"; then
            HAS_VOCABULARY="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Revolution"; then
            HAS_REVOLUTION="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Colony\|Colonies"; then
            HAS_COLONY="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Independence\|Independent"; then
            HAS_INDEPENDENCE="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Patriot"; then
            HAS_PATRIOT="true"
        fi

        # --- Shape counting ---
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

# Create result JSON using Python for safety (avoids bash JSON escaping issues)
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
    "has_do_now": '$HAS_DO_NOW' == 'true',
    "has_objectives": '$HAS_OBJECTIVES' == 'true',
    "has_vocabulary": '$HAS_VOCABULARY' == 'true',
    "has_revolution": '$HAS_REVOLUTION' == 'true',
    "has_colony": '$HAS_COLONY' == 'true',
    "has_independence": '$HAS_INDEPENDENCE' == 'true',
    "has_patriot": '$HAS_PATRIOT' == 'true',
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

# Fallback: write basic JSON if Python fails
if [ ! -f /tmp/task_result.json ]; then
    cat > /tmp/task_result.json << EOF
{
    "file_found": $FILE_FOUND,
    "file_valid": $FILE_VALID,
    "page_count": $PAGE_COUNT,
    "created_during_task": $CREATED_DURING_TASK,
    "has_do_now": $HAS_DO_NOW,
    "has_objectives": $HAS_OBJECTIVES,
    "has_vocabulary": $HAS_VOCABULARY,
    "has_colony": $HAS_COLONY,
    "has_independence": $HAS_INDEPENDENCE,
    "has_patriot": $HAS_PATRIOT,
    "rect_count": $RECT_COUNT
}
EOF
fi

chmod 666 /tmp/task_result.json
echo "Result: $(cat /tmp/task_result.json)"
echo "=== Export Complete ==="
