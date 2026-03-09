#!/bin/bash
# Export script for Math Review Game Board task
# analyzes the created flipchart for content and structure

echo "=== Exporting Math Review Game Board Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/math_review_jeopardy.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/math_review_jeopardy.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
CREATED_DURING_TASK="false"
PAGE_COUNT=0

# Content flags
HAS_TITLE="false"      # "Jeopardy"
HAS_FRACTIONS="false"
HAS_DECIMALS="false"
HAS_PERCENTAGES="false"
HAS_100="false"
HAS_200="false"
HAS_300="false"
HAS_QUESTION="false"   # "3/4"
HAS_ANSWER="false"     # "1/4" or "5/4"

# Shape metrics
RECTANGLE_COUNT=0
TOTAL_SHAPES=0

# Check if file exists
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

    # Check validity (zip format)
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

    # Extract content for deep analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Aggregate all XML text content
        ALL_TEXT=""
        # Only read .xml files to avoid binary garbage
        for XML in "$TMP_DIR"/*.xml "$TMP_DIR"/page*.xml; do
            if [ -f "$XML" ]; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML")"
            fi
        done

        # Check for text requirements (case-insensitive)
        if echo "$ALL_TEXT" | grep -qi "Jeopardy"; then HAS_TITLE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Fractions"; then HAS_FRACTIONS="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Decimals"; then HAS_DECIMALS="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Percentages"; then HAS_PERCENTAGES="true"; fi
        if echo "$ALL_TEXT" | grep -q "100"; then HAS_100="true"; fi
        if echo "$ALL_TEXT" | grep -q "200"; then HAS_200="true"; fi
        if echo "$ALL_TEXT" | grep -q "300"; then HAS_300="true"; fi
        # Question: 3/4 + 1/2
        if echo "$ALL_TEXT" | grep -q "3/4"; then HAS_QUESTION="true"; fi
        # Answer: 1 1/4 or 5/4
        if echo "$ALL_TEXT" | grep -E "1 1/4|5/4|1\.25" -q; then HAS_ANSWER="true"; fi

        # Count Rectangles
        # Look for AsRectangle or type="Rectangle" in XMLs
        # Grep -r returns one line per match, wc -l counts them
        RECTANGLE_COUNT=$(grep -rE 'AsRectangle|type="Rectangle"|shapeType="Rectangle"' "$TMP_DIR" | wc -l)
        
        # Total shapes (generic check)
        TOTAL_SHAPES=$(grep -rE 'AsShape|AsRectangle|AsCircle' "$TMP_DIR" | wc -l)
        
    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON Result
# Using python for safe JSON generation
python3 << PYEOF
import json
import os

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_valid": $FILE_VALID,
    "created_during_task": $CREATED_DURING_TASK,
    "page_count": $PAGE_COUNT,
    "has_title": $HAS_TITLE,
    "has_fractions": $HAS_FRACTIONS,
    "has_decimals": $HAS_DECIMALS,
    "has_percentages": $HAS_PERCENTAGES,
    "has_100": $HAS_100,
    "has_200": $HAS_200,
    "has_300": $HAS_300,
    "has_question": $HAS_QUESTION,
    "has_answer": $HAS_ANSWER,
    "rectangle_count": $RECTANGLE_COUNT,
    "total_shapes": $TOTAL_SHAPES,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="