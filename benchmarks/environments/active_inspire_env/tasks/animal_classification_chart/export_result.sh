#!/bin/bash
# Export script for Animal Classification Chart task
# Extracts content from the flipchart file for verification

echo "=== Exporting Animal Classification Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/animal_classification.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/animal_classification.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Content analysis variables
ALL_TEXT=""
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

    # Check validity (zip archive)
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

    # Extract content
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        # 1. Aggregate all text for keyword searching
        # ActivInspire stores text in various XML tags within the zip
        ALL_TEXT=$(grep -rhE "<text|<AsText" "$TMP_DIR" 2>/dev/null | sed 's/<[^>]*>//g' | tr '\n' ' ' | tr -s ' ')
        
        # Fallback: if specific tags fail, dump all readable strings from XMLs
        if [ -z "$ALL_TEXT" ]; then
             ALL_TEXT=$(find "$TMP_DIR" -name "*.xml" -exec cat {} + | sed 's/<[^>]*>//g' | tr '\n' ' ')
        fi

        # 2. Count shapes (Rectangles)
        # Look for AsRectangle, type="Rectangle", or similar identifiers
        SHAPE_COUNT=$(grep -rhE 'AsRectangle|type="Rectangle"|shapeType="Rectangle"|<Rectangle' "$TMP_DIR" 2>/dev/null | wc -l)
        
        # Fallback: generic shape counting if specific rectangle tags vary by version
        if [ "$SHAPE_COUNT" -eq 0 ]; then
             SHAPE_COUNT=$(grep -rhE 'AsShape' "$TMP_DIR" 2>/dev/null | wc -l)
        fi
    fi
    rm -rf "$TMP_DIR"
fi

# Escape text for JSON safety
SAFE_ALL_TEXT=$(echo "$ALL_TEXT" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')

# Create JSON result file
# We use Python to write the JSON to avoid shell escaping hell with the large text block
python3 << PYEOF
import json
import os

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_valid": '$FILE_VALID' == 'true',
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "page_count": $PAGE_COUNT,
    "extracted_text": """$SAFE_ALL_TEXT""",
    "shape_count": $SHAPE_COUNT,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Fallback if Python fails (shouldn't happen in this env, but safe practice)
if [ ! -f /tmp/task_result.json ]; then
    echo "{" > /tmp/task_result.json
    echo "  \"file_found\": $FILE_FOUND," >> /tmp/task_result.json
    echo "  \"error\": \"Python JSON generation failed\"" >> /tmp/task_result.json
    echo "}" >> /tmp/task_result.json
fi

chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="