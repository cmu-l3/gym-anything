#!/bin/bash
echo "=== Exporting Punnett Square Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
FILE_PATH="/home/ga/Documents/Flipcharts/punnett_square_genetics.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/punnett_square_genetics.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Initialize variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"

# Content flags
HAS_TITLE="false"
HAS_TERMS="false"     # dominant/recessive
HAS_CROSS="false"     # Bb x Bb
HAS_GENOTYPES="false" # BB, Bb, bb
HAS_RATIOS="false"    # 1:2:1 and 3:1
HAS_PRACTICE="false"  # Practice/Try
RECTANGLE_COUNT=0

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

    # Check validity and time
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Analyze content
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Aggregate text from all XML files
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Basic check to ensure it's text/xml
            if file "$XML_FILE" | grep -qi "text\|xml"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE")"
            fi
        done

        # Check for text content
        # Case insensitive grep for robust matching
        if echo "$ALL_TEXT" | grep -qi "Punnett"; then HAS_TITLE="true"; fi
        
        if echo "$ALL_TEXT" | grep -qi "dominant" && \
           echo "$ALL_TEXT" | grep -qi "recessive"; then 
            HAS_TERMS="true"
        fi

        # Flexible matching for cross "Bb x Bb" or similar
        if echo "$ALL_TEXT" | grep -qi "Bb.*x.*Bb" || \
           echo "$ALL_TEXT" | grep -qi "Bb.*Bb"; then
            HAS_CROSS="true"
        fi

        # Check for offspring genotypes (need BB, Bb, bb)
        if echo "$ALL_TEXT" | grep -q "BB" && \
           echo "$ALL_TEXT" | grep -q "Bb" && \
           echo "$ALL_TEXT" | grep -q "bb"; then
            HAS_GENOTYPES="true"
        fi

        # Check for ratios
        if echo "$ALL_TEXT" | grep -q "1:2:1" || echo "$ALL_TEXT" | grep -q "1 : 2 : 1"; then
            if echo "$ALL_TEXT" | grep -q "3:1" || echo "$ALL_TEXT" | grep -q "3 : 1"; then
                HAS_RATIOS="true"
            fi
        fi

        if echo "$ALL_TEXT" | grep -qi "Practice\|Try"; then HAS_PRACTICE="true"; fi

        # Count rectangles
        # Look for shapeType="Rectangle" or similar XML attributes used by ActivInspire
        # Note: grep count across all files
        R_COUNT=$(grep -rEi 'AsRectangle|type="Rectangle"|shapeType="Rectangle"' "$TMP_DIR" | wc -l)
        RECTANGLE_COUNT=$R_COUNT

    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON result
# Using python to write JSON ensures valid formatting
python3 << PYEOF
import json

data = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_valid": $FILE_VALID,
    "page_count": $PAGE_COUNT,
    "created_during_task": $CREATED_DURING_TASK,
    "has_title": $HAS_TITLE,
    "has_terms": $HAS_TERMS,
    "has_cross": $HAS_CROSS,
    "has_genotypes": $HAS_GENOTYPES,
    "has_ratios": $HAS_RATIOS,
    "has_practice": $HAS_PRACTICE,
    "rectangle_count": $RECTANGLE_COUNT,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=4)
PYEOF

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="