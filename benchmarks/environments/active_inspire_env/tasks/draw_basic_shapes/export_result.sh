#!/bin/bash
echo "=== Exporting draw_basic_shapes task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Check for expected file
EXPECTED_FILE="/home/ga/Documents/Flipcharts/shapes_lesson.flipchart"
EXPECTED_FILE_ALT="/home/ga/Documents/Flipcharts/shapes_lesson.flp"

FILE_FOUND="false"
FILE_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_TYPE=""
FILE_VALID="false"
SHAPES_FOUND=0
HAS_RECTANGLE="false"
HAS_CIRCLE="false"

# Check primary expected path
if [ -f "$EXPECTED_FILE" ]; then
    FILE_FOUND="true"
    FILE_PATH="$EXPECTED_FILE"
elif [ -f "$EXPECTED_FILE_ALT" ]; then
    FILE_FOUND="true"
    FILE_PATH="$EXPECTED_FILE_ALT"
fi

# If found, gather file info and analyze content
if [ "$FILE_FOUND" = "true" ]; then
    FILE_SIZE=$(get_file_size "$FILE_PATH")
    FILE_MTIME=$(get_file_mtime "$FILE_PATH")
    FILE_TYPE=$(file -b "$FILE_PATH" 2>/dev/null || echo "unknown")

    # Check if file is valid
    if check_flipchart_file "$FILE_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check if file was created during task
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi

    # Analyze flipchart content for shapes
    # Flipchart files are ZIP archives containing XML with shape definitions
    TEMP_DIR=$(mktemp -d)
    if unzip -q "$FILE_PATH" -d "$TEMP_DIR" 2>/dev/null; then
        # Search for shape definitions in XML files only (not all files)
        # ActivInspire uses specific XML elements for shapes
        # We need to match actual shape elements, NOT just keywords like "rect"
        # which could match "correct", "direction", "BoundingRect" (layout), etc.

        # Look for rectangles - match actual shape element definitions
        # Patterns that indicate an actual rectangle shape:
        # - <Rectangle or <AsRectangle elements
        # - type="Rectangle" or shapeType="Rectangle" attributes
        # - shape="Rectangle" attributes
        # Avoid matching: BoundingRect (layout), textRect, clipRect (internal structure)
        if grep -rqE '<[Aa]s[Rr]ectangle|type="[Rr]ectangle"|shapeType="[Rr]ectangle"|shape="[Rr]ectangle"|<[Rr]ectangle[Ss]hape' "$TEMP_DIR" 2>/dev/null; then
            HAS_RECTANGLE="true"
            SHAPES_FOUND=$((SHAPES_FOUND + 1))
        fi

        # Look for circles/ellipses - match actual shape element definitions
        # Patterns that indicate an actual circle/ellipse shape:
        # - <Circle, <Ellipse, <Oval elements
        # - type="Circle", type="Ellipse" attributes
        # - shapeType="Circle", shapeType="Ellipse" attributes
        if grep -rqE '<[Aa]s[Cc]ircle|<[Aa]s[Ee]llipse|<[Aa]s[Oo]val|type="[Cc]ircle"|type="[Ee]llipse"|shapeType="[Cc]ircle"|shapeType="[Ee]llipse"|shape="[Cc]ircle"|shape="[Ee]llipse"|<[Cc]ircle[Ss]hape|<[Ee]llipse[Ss]hape' "$TEMP_DIR" 2>/dev/null; then
            HAS_CIRCLE="true"
            SHAPES_FOUND=$((SHAPES_FOUND + 1))
        fi

        # Also check for generic drawn shape containers with actual geometry
        # Look for elements that contain drawing data (AsShape with type attribute)
        SHAPE_COUNT=$(grep -rcE '<[Aa]s[Ss]hape[^>]+type=|<[Dd]rawn[Oo]bject|<[Aa]nnotation[Ss]hape' "$TEMP_DIR" 2>/dev/null | awk -F: '{sum += $2} END {print sum+0}')
        if [ "$SHAPE_COUNT" -gt "$SHAPES_FOUND" ]; then
            SHAPES_FOUND=$SHAPE_COUNT
        fi

        # Check for SVG-style path elements that represent actual user drawings
        # Match <path with d= attribute containing actual path commands (M, L, C, Q, A, Z)
        if grep -rqE '<path[^>]+d="[^"]*[MLCQAZmlcqaz][0-9]' "$TEMP_DIR" 2>/dev/null; then
            SHAPES_FOUND=$((SHAPES_FOUND + 1))
        fi
    fi
    rm -rf "$TEMP_DIR"
else
    CREATED_DURING_TASK="false"
fi

# List all flipchart files for debugging
ALL_FLIPCHARTS=$(list_flipcharts /home/ga/Documents/Flipcharts | tr '\n' ',' | sed 's/,$//')

# Create JSON result with properly typed values
# Use json_bool for boolean values to ensure valid JSON output
create_result_json << EOF
{
    "file_found": $(json_bool "$FILE_FOUND"),
    "file_path": "$FILE_PATH",
    "file_size": ${FILE_SIZE:-0},
    "file_mtime": ${FILE_MTIME:-0},
    "file_type": "$FILE_TYPE",
    "file_valid": $(json_bool "$FILE_VALID"),
    "shapes_found": ${SHAPES_FOUND:-0},
    "has_rectangle": $(json_bool "$HAS_RECTANGLE"),
    "has_circle": $(json_bool "$HAS_CIRCLE"),
    "created_during_task": $(json_bool "$CREATED_DURING_TASK"),
    "all_flipcharts": "$ALL_FLIPCHARTS",
    "expected_path": "$EXPECTED_FILE",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
