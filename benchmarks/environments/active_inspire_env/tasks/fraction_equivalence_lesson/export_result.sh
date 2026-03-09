#!/bin/bash
echo "=== Exporting Fraction Equivalence Lesson Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
FILE_PATH="/home/ga/Documents/Flipcharts/fraction_lesson.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/fraction_lesson.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
CREATED_DURING_TASK="false"
PAGE_COUNT=0

# Content Analysis Variables
HAS_NUMERATOR="false"
HAS_DENOMINATOR="false"
COUNT_1_2=0
COUNT_1_4=0
COUNT_1_8=0
RECTANGLE_COUNT=0
COLOR_COUNT=0

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

    # Validate format
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check timestamp
    if [ -n "$FILE_MTIME" ] && [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # EXTRACT AND ANALYZE CONTENT
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Concatenate all XML text for searching
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # Check Vocabulary
        if echo "$ALL_TEXT" | grep -qi "Numerator"; then HAS_NUMERATOR="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Denominator"; then HAS_DENOMINATOR="true"; fi

        # Count Fraction Labels (using grep -o to count occurrences)
        # We look for "1/2", "1 / 2" to handle spacing variations
        COUNT_1_2=$(echo "$ALL_TEXT" | grep -o "1\s*/\s*2" | wc -l)
        COUNT_1_4=$(echo "$ALL_TEXT" | grep -o "1\s*/\s*4" | wc -l)
        COUNT_1_8=$(echo "$ALL_TEXT" | grep -o "1\s*/\s*8" | wc -l)

        # Count Shapes (Rectangles)
        # ActivInspire uses <AsRectangle> or <AsShape type="Rectangle">
        # We count lines containing these patterns
        RECTANGLE_COUNT=$(grep -rE '<[Aa]s[Rr]ectangle|type="[Rr]ectangle"|shapeType="[Rr]ectangle"' "$TMP_DIR" | wc -l)

        # Estimate Color Diversity
        # Look for distinct 'fillColor' or 'color' attributes.
        # This is a heuristic: finding unique color values in the shape definitions
        COLOR_COUNT=$(grep -rhE 'fill[Cc]olor="[^"]+"' "$TMP_DIR" | sort | uniq | wc -l)
        
    fi
    rm -rf "$TMP_DIR"
fi

# Generate JSON Result using Python
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_valid": '$FILE_VALID' == 'true',
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "page_count": $PAGE_COUNT,
    "has_numerator": '$HAS_NUMERATOR' == 'true',
    "has_denominator": '$HAS_DENOMINATOR' == 'true',
    "count_1_2": $COUNT_1_2,
    "count_1_4": $COUNT_1_4,
    "count_1_8": $COUNT_1_8,
    "rectangle_count": $RECTANGLE_COUNT,
    "color_diversity_count": $COLOR_COUNT,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="