#!/bin/bash
# Export script for SWOT Analysis Template task

echo "=== Exporting SWOT Analysis Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target paths
FILE_PATH="/home/ga/Documents/Flipcharts/swot_template.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/swot_template.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Content flags
HAS_TITLE_KEYWORD="false"    # "Device Program" or "SWOT"
HAS_STRENGTHS="false"
HAS_WEAKNESSES="false"
HAS_OPPORTUNITIES="false"
HAS_THREATS="false"

# Structural counts
LINE_COUNT=0
SHAPE_COUNT=0
TOTAL_GRAPHIC_ELEMENTS=0

# 1. Check file existence
if [ -f "$FILE_PATH" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH"
elif [ -f "$FILE_PATH_ALT" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH_ALT"
fi

# 2. Analyze file content if found
if [ "$FILE_FOUND" = "true" ]; then
    FILE_SIZE=$(get_file_size "$ACTUAL_PATH")
    FILE_MTIME=$(get_file_mtime "$ACTUAL_PATH")

    # Validate format (ZIP/XML)
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check timestamp
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Extract and parse XML content
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Aggregate text from all XML files
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # Check for required text
        if echo "$ALL_TEXT" | grep -qi "Device Program\|DeviceProgram"; then
            HAS_TITLE_KEYWORD="true"
        elif echo "$ALL_TEXT" | grep -qi "SWOT"; then
            HAS_TITLE_KEYWORD="true"
        fi

        if echo "$ALL_TEXT" | grep -qi "Strength"; then HAS_STRENGTHS="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Weakness"; then HAS_WEAKNESSES="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Opportunit"; then HAS_OPPORTUNITIES="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Threat"; then HAS_THREATS="true"; fi

        # Check for graphic elements (Lines or Shapes to form the grid)
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII"; then
                # Count Lines
                L=$(grep -ic 'AsLine\|type="Line"' "$XML_FILE" 2>/dev/null || echo 0)
                LINE_COUNT=$((LINE_COUNT + L))
                
                # Count Shapes (Rectangles/Squares)
                S=$(grep -ic 'AsRectangle\|shapeType="Rectangle"\|type="Rectangle"\|AsShape' "$XML_FILE" 2>/dev/null || echo 0)
                SHAPE_COUNT=$((SHAPE_COUNT + S))
            fi
        done
        
        TOTAL_GRAPHIC_ELEMENTS=$((LINE_COUNT + SHAPE_COUNT))
    fi
    rm -rf "$TMP_DIR"
fi

# 3. Create JSON Result
# Using python for safe JSON generation
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_valid": '$FILE_VALID' == 'true',
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "has_title_keyword": '$HAS_TITLE_KEYWORD' == 'true',
    "has_strengths": '$HAS_STRENGTHS' == 'true',
    "has_weaknesses": '$HAS_WEAKNESSES' == 'true',
    "has_opportunities": '$HAS_OPPORTUNITIES' == 'true',
    "has_threats": '$HAS_THREATS' == 'true',
    "line_count": $LINE_COUNT,
    "shape_count": $SHAPE_COUNT,
    "total_graphic_elements": $TOTAL_GRAPHIC_ELEMENTS,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Fallback
if [ ! -f /tmp/task_result.json ]; then
    echo '{"error": "Failed to generate result JSON"}' > /tmp/task_result.json
fi

chmod 666 /tmp/task_result.json
echo "Result JSON generated."
cat /tmp/task_result.json
echo "=== Export Complete ==="