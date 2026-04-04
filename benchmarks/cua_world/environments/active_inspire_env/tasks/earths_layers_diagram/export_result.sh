#!/bin/bash
# Export script for Earth's Layers Diagram task

echo "=== Exporting Earth's Layers Diagram Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/earths_layers.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/earths_layers.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Content flags
HAS_TITLE="false"
HAS_CRUST="false"
HAS_MANTLE="false"
HAS_OUTER_CORE="false"
HAS_INNER_CORE="false"
HAS_TABLE_DATA="false"

# Shape counts
CIRCLE_COUNT=0
RECT_COUNT=0

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

    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract content for analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Combine all XML text for content searching
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # Text Analysis
        if echo "$ALL_TEXT" | grep -qi "Earth.*Layer"; then HAS_TITLE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Crust"; then HAS_CRUST="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Mantle"; then HAS_MANTLE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Outer.*Core"; then HAS_OUTER_CORE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Inner.*Core"; then HAS_INNER_CORE="true"; fi
        
        # Check for table keywords (Thickness, State, Solid, Liquid)
        TABLE_HITS=0
        if echo "$ALL_TEXT" | grep -qi "Thickness"; then TABLE_HITS=$((TABLE_HITS+1)); fi
        if echo "$ALL_TEXT" | grep -qi "State"; then TABLE_HITS=$((TABLE_HITS+1)); fi
        if echo "$ALL_TEXT" | grep -qi "Solid"; then TABLE_HITS=$((TABLE_HITS+1)); fi
        if echo "$ALL_TEXT" | grep -qi "Liquid"; then TABLE_HITS=$((TABLE_HITS+1)); fi
        if [ "$TABLE_HITS" -ge 2 ]; then HAS_TABLE_DATA="true"; fi

        # Shape Analysis (iterate page by page if possible, but global count is okay)
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Count circles/ellipses (for concentric layers)
            C=$(grep -icE 'AsCircle|AsEllipse|AsOval|type="Circle"|type="Ellipse"|shape="Circle"|shape="Ellipse"' "$XML_FILE" 2>/dev/null || echo 0)
            CIRCLE_COUNT=$((CIRCLE_COUNT + C))
            
            # Count rectangles (for table)
            R=$(grep -icE 'AsRectangle|type="Rectangle"|shape="Rectangle"' "$XML_FILE" 2>/dev/null || echo 0)
            RECT_COUNT=$((RECT_COUNT + R))
        done
    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON result using Python
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
    "has_title": '$HAS_TITLE' == 'true',
    "has_crust": '$HAS_CRUST' == 'true',
    "has_mantle": '$HAS_MANTLE' == 'true',
    "has_outer_core": '$HAS_OUTER_CORE' == 'true',
    "has_inner_core": '$HAS_INNER_CORE' == 'true',
    "has_table_data": '$HAS_TABLE_DATA' == 'true',
    "circle_count": $CIRCLE_COUNT,
    "rect_count": $RECT_COUNT,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="