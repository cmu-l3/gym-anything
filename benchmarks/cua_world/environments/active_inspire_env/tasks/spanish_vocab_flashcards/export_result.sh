#!/bin/bash
# Export script for Spanish Vocabulary Flashcards task
# analyzing the created flipchart file.

echo "=== Exporting Spanish Vocab Flashcards Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Define expected paths
FILE_PATH="/home/ga/Documents/Flipcharts/la_casa_vocabulario.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/la_casa_vocabulario.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
SHAPE_COUNT=0

# Initialize text flags
HAS_TITLE_CASA="false"
HAS_SUBTITLE_VOCAB="false"
HAS_COCINA="false"
HAS_KITCHEN="false"
HAS_DORMITORIO="false"
HAS_BEDROOM="false"
HAS_BANO="false"
HAS_BATHROOM="false"

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
    
    # Check if valid flipchart (ZIP/XML)
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Verify creation time
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract and analyze content
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Combine all XML text for searching
        ALL_TEXT=""
        # Iterate over all XML files
        for xml in "$TMP_DIR"/*.xml; do
            if [ -f "$xml" ]; then
                ALL_TEXT="$ALL_TEXT $(cat "$xml")"
            fi
        done
        
        # Search for text terms (case insensitive)
        if echo "$ALL_TEXT" | grep -qi "La Casa"; then HAS_TITLE_CASA="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Vocabulario"; then HAS_SUBTITLE_VOCAB="true"; fi
        if echo "$ALL_TEXT" | grep -qi "cocina"; then HAS_COCINA="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Kitchen"; then HAS_KITCHEN="true"; fi
        if echo "$ALL_TEXT" | grep -qi "dormitorio"; then HAS_DORMITORIO="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Bedroom"; then HAS_BEDROOM="true"; fi
        if echo "$ALL_TEXT" | grep -qi "baño\|bano\|ba&#241;o"; then HAS_BANO="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Bathroom"; then HAS_BATHROOM="true"; fi

        # Count shapes across all XML files
        # Look for Rectangle, Circle, Ellipse, Shape elements
        # Note: grep -c counts lines, not occurrences per line, but usually valid enough for XML elements
        RECTS=$(grep -riE 'AsRectangle|type="Rectangle"|shapeType="Rectangle"' "$TMP_DIR" | wc -l)
        SHAPES=$(grep -riE 'AsShape|type="Shape"' "$TMP_DIR" | wc -l)
        OTHERS=$(grep -riE 'AsCircle|AsEllipse|type="Circle"' "$TMP_DIR" | wc -l)
        
        # Total shapes
        SHAPE_COUNT=$((RECTS + SHAPES + OTHERS))
        
        # Clean up
        rm -rf "$TMP_DIR"
    fi
fi

# Create JSON result using Python to handle boolean/type serialization safely
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
    "shape_count": $SHAPE_COUNT,
    "text_content": {
        "has_title_casa": '$HAS_TITLE_CASA' == 'true',
        "has_subtitle_vocab": '$HAS_SUBTITLE_VOCAB' == 'true',
        "has_cocina": '$HAS_COCINA' == 'true',
        "has_kitchen": '$HAS_KITCHEN' == 'true',
        "has_dormitorio": '$HAS_DORMITORIO' == 'true',
        "has_bedroom": '$HAS_BEDROOM' == 'true',
        "has_bano": '$HAS_BANO' == 'true',
        "has_bathroom": '$HAS_BATHROOM' == 'true'
    },
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="