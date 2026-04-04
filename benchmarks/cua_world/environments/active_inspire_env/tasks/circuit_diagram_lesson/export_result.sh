#!/bin/bash
# Export script for Circuit Diagram Lesson task
# Analyzes the flipchart structure, text content, and shape usage

echo "=== Exporting Circuit Diagram Lesson Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Define expected paths
FILE_PATH="/home/ga/Documents/Flipcharts/circuit_diagram_lesson.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/circuit_diagram_lesson.flp"

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
HAS_TITLE_INTRO="false"
HAS_SERIES_TEXT="false"
HAS_PARALLEL_TEXT="false"
HAS_BATTERY="false"
HAS_BULB_OR_RESISTOR="false"
HAS_SWITCH="false"

# Page-specific analysis
SHAPES_PAGE_2=0
SHAPES_PAGE_3=0
TEXT_PAGE_2=""
TEXT_PAGE_3=""

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

    # Validate file format (ZIP/XML)
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check timestamp against task start
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Deep content analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # 1. Gather all text for general keyword checking
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # Check required terms
        if echo "$ALL_TEXT" | grep -qi "Circuit"; then HAS_TITLE_INTRO="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Series"; then HAS_SERIES_TEXT="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Parallel"; then HAS_PARALLEL_TEXT="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Battery"; then HAS_BATTERY="true"; fi
        if echo "$ALL_TEXT" | grep -qiE "Bulb|Resistor|Lamp|Light"; then HAS_BULB_OR_RESISTOR="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Switch"; then HAS_SWITCH="true"; fi

        # 2. Page-specific shape counting
        # ActivInspire often names page files like page001.xml, page002.xml
        # or defines pages in a main xml. We try to find specific page files.
        
        # Sort files to guess page order
        PAGE_FILES=$(find "$TMP_DIR" -name "page*.xml" | sort)
        
        # If no separate page files found, we might have a single large XML. 
        # In that case, we can't easily distinguish page 2 vs 3 shapes programmatically 
        # without complex parsing. We'll fallback to total shapes if needed, 
        # but try to split by <page> tag if possible.
        
        NUM_PAGE_FILES=$(echo "$PAGE_FILES" | wc -w)
        
        if [ "$NUM_PAGE_FILES" -ge 3 ]; then
            # We have distinct page files
            PAGE_2_FILE=$(echo "$PAGE_FILES" | awk '{print $2}')
            PAGE_3_FILE=$(echo "$PAGE_FILES" | awk '{print $3}')
            
            # Count shapes on Page 2 (Series)
            if [ -f "$PAGE_2_FILE" ]; then
                SHAPES_PAGE_2=$(grep -icE 'AsShape|AsRectangle|AsLine|AsEllipse|AsCircle|type="Rectangle"|type="Line"' "$PAGE_2_FILE" || echo 0)
                TEXT_PAGE_2=$(cat "$PAGE_2_FILE")
            fi
            
            # Count shapes on Page 3 (Parallel)
            if [ -f "$PAGE_3_FILE" ]; then
                SHAPES_PAGE_3=$(grep -icE 'AsShape|AsRectangle|AsLine|AsEllipse|AsCircle|type="Rectangle"|type="Line"' "$PAGE_3_FILE" || echo 0)
                TEXT_PAGE_3=$(cat "$PAGE_3_FILE")
            fi
        else
            # Fallback: Count total shapes and divide roughly or check main XML
            # This is less precise but necessary if format varies
            TOTAL_SHAPES=$(grep -icE 'AsShape|AsRectangle|AsLine' "$TMP_DIR"/*.xml || echo 0)
            SHAPES_PAGE_2=$((TOTAL_SHAPES / 3))
            SHAPES_PAGE_3=$((TOTAL_SHAPES / 3))
        fi
        
    fi
    rm -rf "$TMP_DIR"
fi

# Use Python to generate safe JSON
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
    "has_title_intro": '$HAS_TITLE_INTRO' == 'true',
    "has_series_text": '$HAS_SERIES_TEXT' == 'true',
    "has_parallel_text": '$HAS_PARALLEL_TEXT' == 'true',
    "has_battery": '$HAS_BATTERY' == 'true',
    "has_bulb_or_resistor": '$HAS_BULB_OR_RESISTOR' == 'true',
    "has_switch": '$HAS_SWITCH' == 'true',
    "shapes_page_2": $SHAPES_PAGE_2,
    "shapes_page_3": $SHAPES_PAGE_3,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON written successfully")
PYEOF

chmod 666 /tmp/task_result.json
echo "Result contents:"
cat /tmp/task_result.json
echo "=== Export Complete ==="