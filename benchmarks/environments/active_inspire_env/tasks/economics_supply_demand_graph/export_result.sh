#!/bin/bash
# Export script for Economics Graph task
echo "=== Exporting Economics Graph Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Target paths
FILE_PATH="/home/ga/Documents/Flipcharts/supply_demand_lesson.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/supply_demand_lesson.flp"

# Initialize variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Content flags
HAS_PRICE="false"
HAS_QUANTITY="false"
HAS_SUPPLY="false"
HAS_DEMAND="false"
HAS_EQUILIBRIUM="false"
HAS_SHIFT="false"
LINE_COUNT=0
ARROW_COUNT=0

# Check file existence
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

    # Check validity
    if check_flipchart_file "$ACTUAL_PATH"; then
        FILE_VALID="true"
    fi

    # Check timestamp
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Analyze content
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Aggregate text from all XMLs
        ALL_TEXT=""
        for XML in "$TMP_DIR"/*.xml; do
            [ -f "$XML" ] || continue
            if file "$XML" 2>/dev/null | grep -qi "xml\|text"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML")"
            fi
        done

        # Check for required text
        if echo "$ALL_TEXT" | grep -qi "Price\| P "; then HAS_PRICE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Quantity\| Q "; then HAS_QUANTITY="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Supply\| S "; then HAS_SUPPLY="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Demand\| D "; then HAS_DEMAND="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Equilibrium"; then HAS_EQUILIBRIUM="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Shift\|Increase"; then HAS_SHIFT="true"; fi

        # Count shapes/lines
        # Looking for lines (AsLine, AsPolyLine) and arrows
        for XML in "$TMP_DIR"/*.xml; do
            [ -f "$XML" ] || continue
            if file "$XML" 2>/dev/null | grep -qi "xml\|text"; then
                # Count lines/segments
                L=$(grep -ic 'AsLine\|AsPolyLine\|type="Line"' "$XML" 2>/dev/null || echo 0)
                LINE_COUNT=$((LINE_COUNT + L))
                
                # Count arrows
                A=$(grep -ic 'AsArrow\|endCap="Arrow"\|startCap="Arrow"' "$XML" 2>/dev/null || echo 0)
                ARROW_COUNT=$((ARROW_COUNT + A))
            fi
        done
    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON result
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
    "has_price": '$HAS_PRICE' == 'true',
    "has_quantity": '$HAS_QUANTITY' == 'true',
    "has_supply": '$HAS_SUPPLY' == 'true',
    "has_demand": '$HAS_DEMAND' == 'true',
    "has_equilibrium": '$HAS_EQUILIBRIUM' == 'true',
    "has_shift": '$HAS_SHIFT' == 'true',
    "line_count": $LINE_COUNT,
    "arrow_count": $ARROW_COUNT,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
cat /tmp/task_result.json
echo "=== Export Complete ==="