#!/bin/bash
# Export script for States of Matter Particle Model task

echo "=== Exporting Task Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
FILE_PATH="/home/ga/Documents/Flipcharts/particle_model.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/particle_model.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"

# Text Content Flags
HAS_SOLID="false"
HAS_LIQUID="false"
HAS_GAS="false"

# Shape Counts
RECT_COUNT=0
CIRCLE_COUNT=0

# Color Heuristics (looking for color definitions in XML)
# ActivInspire often uses decimal or hex integer representations for colors
# We will look for rough indicators of "Red" (e.g. 0xFFFF0000 or similar) inside the file content
HAS_RED_COLOR="false"
HAS_BLUE_COLOR="false"

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

    # Check validity (is it a zip?)
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check creation time
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Analyze content
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract XML to temporary directory for analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # 1. Text Analysis
        # Search all XML files for the required strings
        ALL_TEXT=$(grep -rIh "<text" "$TMP_DIR" 2>/dev/null || echo "")
        
        if echo "$ALL_TEXT" | grep -qi "Solid"; then HAS_SOLID="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Liquid"; then HAS_LIQUID="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Gas"; then HAS_GAS="true"; fi

        # 2. Shape Analysis
        # Search for Rectangle shapes
        RECT_COUNT=$(grep -rIcE 'AsRectangle|type="Rectangle"|shapeType="Rectangle"' "$TMP_DIR" | awk -F: '{s+=$2} END {print s}')
        
        # Search for Circle/Ellipse shapes
        CIRCLE_COUNT=$(grep -rIcE 'AsCircle|AsEllipse|type="Circle"|type="Ellipse"' "$TMP_DIR" | awk -F: '{s+=$2} END {print s}')

        # 3. Color Analysis (Heuristic)
        # Look for color attributes. Red often appears as 4294901760 (0xFFFF0000) or similar high values
        # Blue often appears as 4278190335 (0xFF0000FF)
        # We also look for color names if stored that way
        ALL_CONTENT=$(cat "$TMP_DIR"/*.xml 2>/dev/null)
        
        # Check for Red indicators
        if echo "$ALL_CONTENT" | grep -qiE '4294901760|0xFFFF0000|Red'; then
            HAS_RED_COLOR="true"
        fi
        
        # Check for Blue indicators
        if echo "$ALL_CONTENT" | grep -qiE '4278190335|0xFF0000FF|Blue'; then
            HAS_BLUE_COLOR="true"
        fi

        rm -rf "$TMP_DIR"
    fi
fi

# Create JSON result
# Using python for safe JSON formatting
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
    "has_solid": $HAS_SOLID,
    "has_liquid": $HAS_LIQUID,
    "has_gas": $HAS_GAS,
    "rect_count": $RECT_COUNT,
    "circle_count": $CIRCLE_COUNT,
    "has_red_color": $HAS_RED_COLOR,
    "has_blue_color": $HAS_BLUE_COLOR,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="