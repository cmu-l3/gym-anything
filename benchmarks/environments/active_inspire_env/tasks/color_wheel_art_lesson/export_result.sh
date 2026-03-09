#!/bin/bash
echo "=== Exporting Color Wheel Art Lesson Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/color_wheel_art.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/color_wheel_art.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"

# Text Content Flags
HAS_TITLE_THEORY="false"
HAS_TITLE_ELEMENTS="false"
HAS_RED="false"
HAS_YELLOW="false"
HAS_BLUE="false"
HAS_ORANGE="false"
HAS_GREEN="false"
HAS_VIOLET="false"

# Art Elements Flags
FOUND_ELEMENTS_COUNT=0
ELEMENTS_LIST=("Line" "Shape" "Form" "Space" "Color" "Value" "Texture")

# Shape Count
SHAPE_COUNT=0

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
    
    # Check if created/modified during task
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Check validity and page count
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
        PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")
    fi

    # ANALYZE CONTENT (Unzip and grep XML)
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Concatenate all XML text for searching strings
        ALL_XML_TEXT=""
        for xml in "$TMP_DIR"/*.xml; do
            [ -f "$xml" ] && ALL_XML_TEXT="${ALL_XML_TEXT} $(cat "$xml")"
        done

        # 1. Check Titles
        if echo "$ALL_XML_TEXT" | grep -qi "Color Theory"; then HAS_TITLE_THEORY="true"; fi
        if echo "$ALL_XML_TEXT" | grep -qi "Elements of Art"; then HAS_TITLE_ELEMENTS="true"; fi

        # 2. Check Colors (Text Labels)
        if echo "$ALL_XML_TEXT" | grep -qi "Red"; then HAS_RED="true"; fi
        if echo "$ALL_XML_TEXT" | grep -qi "Yellow"; then HAS_YELLOW="true"; fi
        if echo "$ALL_XML_TEXT" | grep -qi "Blue"; then HAS_BLUE="true"; fi
        if echo "$ALL_XML_TEXT" | grep -qi "Orange"; then HAS_ORANGE="true"; fi
        if echo "$ALL_XML_TEXT" | grep -qi "Green"; then HAS_GREEN="true"; fi
        if echo "$ALL_XML_TEXT" | grep -qiE "Violet|Purple"; then HAS_VIOLET="true"; fi

        # 3. Check Art Elements List
        for elem in "${ELEMENTS_LIST[@]}"; do
            if echo "$ALL_XML_TEXT" | grep -qi "$elem"; then
                FOUND_ELEMENTS_COUNT=$((FOUND_ELEMENTS_COUNT + 1))
            fi
        done

        # 4. Count Shapes
        # Count occurrences of shape definitions in XML
        # Common ActivInspire XML tags for shapes: AsShape, AsRectangle, AsCircle, AsEllipse
        # Also attributes like type="Rectangle"
        SHAPE_COUNT=$(grep -orcE "AsShape|AsRectangle|AsCircle|AsEllipse|type=\"Rectangle\"|type=\"Circle\"|type=\"Ellipse\"|type=\"Shape\"" "$TMP_DIR"/*.xml | awk -F: '{sum+=$2} END {print sum}')
        
    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON result
# Using Python for robust JSON creation
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_valid": $FILE_VALID,
    "page_count": $PAGE_COUNT,
    "created_during_task": $CREATED_DURING_TASK,
    "content": {
        "has_title_theory": $HAS_TITLE_THEORY,
        "has_title_elements": $HAS_TITLE_ELEMENTS,
        "has_red": $HAS_RED,
        "has_yellow": $HAS_YELLOW,
        "has_blue": $HAS_BLUE,
        "has_orange": $HAS_ORANGE,
        "has_green": $HAS_GREEN,
        "has_violet": $HAS_VIOLET,
        "found_elements_count": $FOUND_ELEMENTS_COUNT,
        "shape_count": $SHAPE_COUNT
    },
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="