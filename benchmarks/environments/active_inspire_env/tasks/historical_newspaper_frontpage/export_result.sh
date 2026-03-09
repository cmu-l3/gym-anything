#!/bin/bash
echo "=== Exporting Historical Newspaper Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/independence_gazette.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/independence_gazette.flp"

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
HAS_MASTHEAD="false"       # Independence Gazette
HAS_DATELINE="false"       # Philadelphia + 1776
HAS_HEADLINE="false"       # Independence Declared
HAS_BYLINE="false"         # Benjamin Harris
HAS_BODY="false"           # Continental Congress OR Declaration
HAS_SIDEBAR="false"        # King George
HAS_ASSIGNMENT="false"     # Assignment (Page 2 check)

# Shape counts
LINE_COUNT=0
RECT_COUNT=0
TOTAL_SHAPE_COUNT=0

# Check for file existence
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

    # Validate format
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check timestamp
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract content for analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Aggregate text from all XML files
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Basic check to see if it's text/xml
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # --- Text Analysis ---
        # Case insensitive grep for content
        if echo "$ALL_TEXT" | grep -qi "Independence Gazette"; then HAS_MASTHEAD="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Philadelphia" && echo "$ALL_TEXT" | grep -qi "1776"; then HAS_DATELINE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Independence Declared"; then HAS_HEADLINE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Benjamin Harris"; then HAS_BYLINE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Continental Congress\|Declaration of Independence"; then HAS_BODY="true"; fi
        if echo "$ALL_TEXT" | grep -qi "King George"; then HAS_SIDEBAR="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Assignment"; then HAS_ASSIGNMENT="true"; fi

        # --- Shape Analysis ---
        # Count shape elements in XMLs
        # ActivInspire XML uses AsLine, AsRectangle, AsShape, etc.
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            
            # Lines (for column dividers)
            L=$(grep -ic 'AsLine\|shapeType="Line"\|type="Line"' "$XML_FILE" 2>/dev/null || echo 0)
            
            # Rectangles (for boxes/dividers)
            R=$(grep -ic 'AsRectangle\|shapeType="Rectangle"\|type="Rectangle"' "$XML_FILE" 2>/dev/null || echo 0)
            
            # Generic shapes
            S=$(grep -ic 'AsShape' "$XML_FILE" 2>/dev/null || echo 0)
            
            LINE_COUNT=$((LINE_COUNT + L))
            RECT_COUNT=$((RECT_COUNT + R))
            TOTAL_SHAPE_COUNT=$((TOTAL_SHAPE_COUNT + S))
        done
        
        # Adjust total to ensure it captures lines/rects if AsShape wasn't used
        if [ $LINE_COUNT -gt 0 ] || [ $RECT_COUNT -gt 0 ]; then
             # Simple max logic or addition depending on how XML is structured
             # Often AsShape wraps type="Rectangle", so S counts R. 
             # But AsLine might be distinct.
             # We'll rely on specific counts for criteria.
             true
        fi
    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON result safely using Python
python3 << PYEOF
import json
import os

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_valid": '$FILE_VALID' == 'true',
    "page_count": $PAGE_COUNT,
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "has_masthead": '$HAS_MASTHEAD' == 'true',
    "has_dateline": '$HAS_DATELINE' == 'true',
    "has_headline": '$HAS_HEADLINE' == 'true',
    "has_byline": '$HAS_BYLINE' == 'true',
    "has_body": '$HAS_BODY' == 'true',
    "has_sidebar": '$HAS_SIDEBAR' == 'true',
    "has_assignment": '$HAS_ASSIGNMENT' == 'true',
    "line_count": $LINE_COUNT,
    "rect_count": $RECT_COUNT,
    "total_shape_count": $TOTAL_SHAPE_COUNT,
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
echo "Result generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="