#!/bin/bash
# Export script for Simple Machines Diagrams task

echo "=== Exporting Simple Machines Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/simple_machines_lesson.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/simple_machines_lesson.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Text content flags
HAS_TITLE="false"
HAS_LIST_ITEMS="false"
HAS_LEVER_DEF="false"
HAS_LEVER_LABELS="false"
HAS_RAMP_DEF="false"
HAS_RAMP_LABEL="false"

# Shape counts
TRIANGLE_COUNT=0
RECT_LINE_COUNT=0
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

    # Check creation time
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract content for analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then

        # Collect text from all XML files
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # --- Text Analysis ---
        # Page 1: Title and List
        if echo "$ALL_TEXT" | grep -qi "Simple Machines"; then
            HAS_TITLE="true"
        fi
        # Check for a few list items to confirm list existence
        if echo "$ALL_TEXT" | grep -qi "Wedge" && echo "$ALL_TEXT" | grep -qi "Screw"; then
            HAS_LIST_ITEMS="true"
        fi

        # Page 2: Lever Definition and Labels
        if echo "$ALL_TEXT" | grep -qi "rigid bar\|pivot"; then
            HAS_LEVER_DEF="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Fulcrum" && echo "$ALL_TEXT" | grep -qi "Load"; then
            HAS_LEVER_LABELS="true"
        fi

        # Page 3: Inclined Plane Definition and Label
        if echo "$ALL_TEXT" | grep -qi "tilted\|angle\|surface"; then
            HAS_RAMP_DEF="true"
        fi
        if echo "$ALL_TEXT" | grep -qi "Ramp"; then
            HAS_RAMP_LABEL="true"
        fi

        # --- Shape Analysis ---
        # Search XML files for shape definitions
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            
            # Count Triangles (Fulcrum, Ramp)
            T=$(grep -ic 'AsTriangle\|shapeType="Triangle"\|type="Triangle"' "$XML_FILE" 2>/dev/null || echo 0)
            TRIANGLE_COUNT=$((TRIANGLE_COUNT + T))

            # Count Rectangles or Lines (Beam)
            R=$(grep -ic 'AsRectangle\|shapeType="Rectangle"\|type="Rectangle"' "$XML_FILE" 2>/dev/null || echo 0)
            L=$(grep -ic 'AsLine\|shapeType="Line"\|type="Line"' "$XML_FILE" 2>/dev/null || echo 0)
            RECT_LINE_COUNT=$((RECT_LINE_COUNT + R + L))

            # Total shapes (including Circles/Squares for load/object)
            S=$(grep -ic 'AsShape\|AsRectangle\|AsTriangle\|AsCircle\|AsLine' "$XML_FILE" 2>/dev/null || echo 0)
            TOTAL_SHAPE_COUNT=$((TOTAL_SHAPE_COUNT + S))
        done
    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON result
# Use python for safer JSON generation
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_valid": $FILE_VALID,
    "page_count": $PAGE_COUNT,
    "created_during_task": $CREATED_DURING_TASK,
    "has_title": $HAS_TITLE,
    "has_list_items": $HAS_LIST_ITEMS,
    "has_lever_def": $HAS_LEVER_DEF,
    "has_lever_labels": $HAS_LEVER_LABELS,
    "has_ramp_def": $HAS_RAMP_DEF,
    "has_ramp_label": $HAS_RAMP_LABEL,
    "triangle_count": $TRIANGLE_COUNT,
    "rect_line_count": $RECT_LINE_COUNT,
    "total_shape_count": $TOTAL_SHAPE_COUNT,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written:"
cat /tmp/task_result.json
echo "=== Export Complete ==="