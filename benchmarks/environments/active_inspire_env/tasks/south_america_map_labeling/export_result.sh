#!/bin/bash
# Export script for South America Map Labeling task

echo "=== Exporting South America Map Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
take_screenshot /tmp/task_end.png

# 2. Paths and Variables
FILE_PATH="/home/ga/Documents/Flipcharts/south_america_map.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/south_america_map.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
CREATED_DURING_TASK="false"
PAGE_COUNT=0

# Content Detection
HAS_TITLE="false"
HAS_LABEL_MAP_TEXT="false"
HAS_IMAGE="false"
POINTER_COUNT=0

# Countries Found
HAS_BRAZIL="false"
HAS_ARGENTINA="false"
HAS_COLOMBIA="false"
HAS_PERU="false"
HAS_CHILE="false"
HAS_VENEZUELA="false"

# 3. Check File Existence
if [ -f "$FILE_PATH" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH"
elif [ -f "$FILE_PATH_ALT" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH_ALT"
fi

# 4. Analyze File Content
if [ "$FILE_FOUND" = "true" ]; then
    FILE_SIZE=$(get_file_size "$ACTUAL_PATH")
    FILE_MTIME=$(get_file_mtime "$ACTUAL_PATH")

    if check_flipchart_file "$ACTUAL_PATH"; then
        FILE_VALID="true"
    fi

    # Check timing
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Unzip and grep content
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Concatenate all XML text for searching
        ALL_TEXT=""
        for XML in "$TMP_DIR"/*.xml; do
            [ -f "$XML" ] && ALL_TEXT="$ALL_TEXT $(cat "$XML")"
        done

        # Check Text Requirements
        echo "$ALL_TEXT" | grep -qi "South America" && HAS_TITLE="true"
        echo "$ALL_TEXT" | grep -qi "Label the Map" && HAS_LABEL_MAP_TEXT="true"

        echo "$ALL_TEXT" | grep -qi "Brazil" && HAS_BRAZIL="true"
        echo "$ALL_TEXT" | grep -qi "Argentina" && HAS_ARGENTINA="true"
        echo "$ALL_TEXT" | grep -qi "Colombia" && HAS_COLOMBIA="true"
        echo "$ALL_TEXT" | grep -qi "Peru" && HAS_PERU="true"
        echo "$ALL_TEXT" | grep -qi "Chile" && HAS_CHILE="true"
        echo "$ALL_TEXT" | grep -qi "Venezuela" && HAS_VENEZUELA="true"

        # Check for Image (AsImage tag or resource references)
        # Flipcharts usually store images in an 'images' folder inside the zip or reference them
        if [ -d "$TMP_DIR/images" ] && [ "$(ls -A $TMP_DIR/images 2>/dev/null)" ]; then
            HAS_IMAGE="true"
        elif grep -rqE '<[Aa]s[Ii]mage' "$TMP_DIR"; then
            HAS_IMAGE="true"
        fi

        # Check for Pointers (Lines/Arrows)
        # Search for AsLine, AsArrow, or shapes with type="Line"/"Arrow"
        POINTER_COUNT=$(grep -rcE '<[Aa]s[Ll]ine|<[Aa]s[Aa]rrow|type="[Ll]ine"|type="[Aa]rrow"|shape="[Aa]rrow"|shape="[Ll]ine"' "$TMP_DIR" | awk -F: '{sum+=$2} END {print sum+0}')
        
    fi
    rm -rf "$TMP_DIR"
fi

# 5. Create Result JSON (Python for safe serialization)
python3 << PYEOF
import json

data = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_valid": '$FILE_VALID' == 'true',
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "page_count": $PAGE_COUNT,
    "has_title": '$HAS_TITLE' == 'true',
    "has_label_map_text": '$HAS_LABEL_MAP_TEXT' == 'true',
    "has_image": '$HAS_IMAGE' == 'true',
    "pointer_count": $POINTER_COUNT,
    "countries": {
        "Brazil": '$HAS_BRAZIL' == 'true',
        "Argentina": '$HAS_ARGENTINA' == 'true',
        "Colombia": '$HAS_COLOMBIA' == 'true',
        "Peru": '$HAS_PERU' == 'true',
        "Chile": '$HAS_CHILE' == 'true',
        "Venezuela": '$HAS_VENEZUELA' == 'true'
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Result JSON created."
cat /tmp/task_result.json
echo "=== Export Complete ==="