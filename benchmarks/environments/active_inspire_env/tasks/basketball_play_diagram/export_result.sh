#!/bin/bash
# Export script for Basketball Playbook task
# Extracts content from the flipchart file (ZIP/XML) and generates a JSON result.

echo "=== Exporting Basketball Playbook Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved."

# Define paths
FILE_PATH="/home/ga/Documents/Flipcharts/basketball_playbook.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/basketball_playbook.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"

# Content flags
HAS_TITLE_COURT="false"
HAS_TITLE_STARTERS="false"
HAS_TITLE_PLAY="false"
HAS_TEXT_SCREEN="false"

# Position counters
POSITIONS_FOUND=0
HAS_PG="false"
HAS_SG="false"
HAS_SF="false"
HAS_PF="false"
HAS_C="false"

# Shape counters
RECT_COUNT=0
CIRCLE_COUNT=0
LINE_COUNT=0
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

    # Check validity (is it a zip/flipchart?)
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check timestamp
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Analyze content
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Aggregate all text from XML files
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Basic check to ensure it's text/xml
            if file "$XML_FILE" 2>/dev/null | grep -qiE "xml|text|ASCII|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # Check required text strings
        if echo "$ALL_TEXT" | grep -qi "Half Court"; then HAS_TITLE_COURT="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Offensive Starters"; then HAS_TITLE_STARTERS="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Pick and Roll"; then HAS_TITLE_PLAY="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Screen"; then HAS_TEXT_SCREEN="true"; fi

        # Check positions (exact matches preferred, but flexible with grep)
        if echo "$ALL_TEXT" | grep -q "PG"; then HAS_PG="true"; ((POSITIONS_FOUND++)); fi
        if echo "$ALL_TEXT" | grep -q "SG"; then HAS_SG="true"; ((POSITIONS_FOUND++)); fi
        if echo "$ALL_TEXT" | grep -q "SF"; then HAS_SF="true"; ((POSITIONS_FOUND++)); fi
        if echo "$ALL_TEXT" | grep -q "PF"; then HAS_PF="true"; ((POSITIONS_FOUND++)); fi
        if echo "$ALL_TEXT" | grep -q "C[^a-z]"; then HAS_C="true"; ((POSITIONS_FOUND++)); fi # "C" not followed by letter (avoid matches like "Court")

        # Check shapes in XML
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            
            # Rectangles
            R=$(grep -icE 'AsRectangle|type="Rectangle"|shapeType="Rectangle"' "$XML_FILE" || echo 0)
            RECT_COUNT=$((RECT_COUNT + R))

            # Circles
            C=$(grep -icE 'AsCircle|AsEllipse|type="Circle"|type="Ellipse"' "$XML_FILE" || echo 0)
            CIRCLE_COUNT=$((CIRCLE_COUNT + C))

            # Lines/Arrows
            L=$(grep -icE 'AsLine|type="Line"|AsArrow|type="Arrow"|<path' "$XML_FILE" || echo 0)
            LINE_COUNT=$((LINE_COUNT + L))
        done
        
        TOTAL_SHAPES=$((RECT_COUNT + CIRCLE_COUNT + LINE_COUNT))
    fi
    rm -rf "$TMP_DIR"
fi

# Generate JSON result using Python to ensure valid format
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_valid": '$FILE_VALID' == 'true',
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "page_count": $PAGE_COUNT,
    "has_title_court": '$HAS_TITLE_COURT' == 'true',
    "has_title_starters": '$HAS_TITLE_STARTERS' == 'true',
    "has_title_play": '$HAS_TITLE_PLAY' == 'true',
    "has_text_screen": '$HAS_TEXT_SCREEN' == 'true',
    "positions_found_count": $POSITIONS_FOUND,
    "has_pg": '$HAS_PG' == 'true',
    "has_sg": '$HAS_SG' == 'true',
    "has_sf": '$HAS_SF' == 'true',
    "has_pf": '$HAS_PF' == 'true',
    "has_c": '$HAS_C' == 'true',
    "rect_count": $RECT_COUNT,
    "circle_count": $CIRCLE_COUNT,
    "line_count": $LINE_COUNT,
    "total_shapes": $TOTAL_SHAPES,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("JSON result generated.")
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json