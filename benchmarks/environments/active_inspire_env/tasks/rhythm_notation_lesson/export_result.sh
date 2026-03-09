#!/bin/bash
# Export script for Rhythm Notation Lesson task
# Analyzes the created flipchart for content verification

echo "=== Exporting Rhythm Notation Lesson Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/rhythm_basics.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/rhythm_basics.flp"

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
HAS_TITLE_RHYTHM="false"
HAS_WHOLE_NOTE="false"
HAS_HALF_NOTE="false"
HAS_QUARTER_NOTE="false"
HAS_EIGHTH_NOTE="false"
HAS_BEAT_VALUES="false"
HAS_COUNTING="false"
HAS_CLAP_ACTIVITY="false"

# Shape counts
CIRCLE_ELLIPSE_COUNT=0
TOTAL_SHAPE_COUNT=0

# Check primary path, then alt
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

    # Validate flipchart format
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check creation time vs task start
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract content for text and shape analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then

        # Collect text from all XML files
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Basic check to ensure it's text-readable
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # --- Text content checks ---
        if echo "$ALL_TEXT" | grep -qi "Rhythm"; then
            HAS_TITLE_RHYTHM="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Whole Note"; then
            HAS_WHOLE_NOTE="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Half Note"; then
            HAS_HALF_NOTE="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Quarter Note"; then
            HAS_QUARTER_NOTE="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Eighth Note"; then
            HAS_EIGHTH_NOTE="true"
        fi
        
        # Check for beat values (e.g., "4 beats", "1 beat")
        if echo "$ALL_TEXT" | grep -qiE "[0-9]+ beat|beat"; then
            HAS_BEAT_VALUES="true"
        fi

        # Check for counting numbers
        if echo "$ALL_TEXT" | grep -q "1" && echo "$ALL_TEXT" | grep -q "2" && \
           echo "$ALL_TEXT" | grep -q "3" && echo "$ALL_TEXT" | grep -q "4"; then
            HAS_COUNTING="true"
        fi

        # Check for activity keywords
        if echo "$ALL_TEXT" | grep -qiE "Clap|Practice|Activity"; then
            HAS_CLAP_ACTIVITY="true"
        fi

        # --- Shape counting ---
        # Look for circles/ellipses used for note heads
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII"; then
                # Count ellipses/circles
                C=$(grep -ic 'AsCircle\|AsEllipse\|AsOval\|type="Circle"\|type="Ellipse"' "$XML_FILE" 2>/dev/null || echo 0)
                # Count all shapes
                S=$(grep -ic 'AsShape' "$XML_FILE" 2>/dev/null || echo 0)
                
                CIRCLE_ELLIPSE_COUNT=$((CIRCLE_ELLIPSE_COUNT + C))
                TOTAL_SHAPE_COUNT=$((TOTAL_SHAPE_COUNT + S))
            fi
        done
    fi
    rm -rf "$TMP_DIR"
fi

# Create result JSON using Python for safe formatting
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
    "has_title_rhythm": '$HAS_TITLE_RHYTHM' == 'true',
    "has_whole_note": '$HAS_WHOLE_NOTE' == 'true',
    "has_half_note": '$HAS_HALF_NOTE' == 'true',
    "has_quarter_note": '$HAS_QUARTER_NOTE' == 'true',
    "has_eighth_note": '$HAS_EIGHTH_NOTE' == 'true',
    "has_beat_values": '$HAS_BEAT_VALUES' == 'true',
    "has_counting": '$HAS_COUNTING' == 'true',
    "has_clap_activity": '$HAS_CLAP_ACTIVITY' == 'true',
    "circle_ellipse_count": $CIRCLE_ELLIPSE_COUNT,
    "total_shape_count": $TOTAL_SHAPE_COUNT,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON written successfully")
PYEOF

# Fallback in case Python fails
if [ ! -f /tmp/task_result.json ]; then
    echo '{"file_found": false, "error": "Export failed"}' > /tmp/task_result.json
fi

chmod 666 /tmp/task_result.json
echo "Result contents:"
cat /tmp/task_result.json
echo "=== Export Complete ==="