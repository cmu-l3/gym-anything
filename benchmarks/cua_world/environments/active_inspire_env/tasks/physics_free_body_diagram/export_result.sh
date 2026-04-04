#!/bin/bash
echo "=== Exporting Physics FBD Task Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
FILE_PATH="/home/ga/Documents/Flipcharts/physics_fbd.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/physics_fbd.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"

# Content flags
HAS_TITLE_TEXT="false"
HAS_NEWTON_TEXT="false"
HAS_REST_TEXT="false"
HAS_RAMP_TEXT="false"
HAS_FG="false"
HAS_FN="false"
HAS_FF="false"
HAS_FNET="false"
HAS_TRIANGLE="false"
HAS_RECTANGLE="false"
HAS_ROTATION="false"

# Check existence
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
    
    # Check validity and timestamp
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Deep content analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        # Concatenate all XML content
        ALL_XML=$(cat "$TMP_DIR"/*.xml 2>/dev/null)
        
        # Check text
        echo "$ALL_XML" | grep -qi "Free Body" && HAS_TITLE_TEXT="true"
        echo "$ALL_XML" | grep -qi "Newton" && HAS_NEWTON_TEXT="true"
        echo "$ALL_XML" | grep -qi "Rest" && HAS_REST_TEXT="true"
        echo "$ALL_XML" | grep -qi "Ramp" && HAS_RAMP_TEXT="true"
        # Check for Fg, Fn, Ff, Fnet (using grep word boundaries or surrounding quotes to avoid partial matches inside other words if possible, though strictness here might be tricky with XML encoding)
        echo "$ALL_XML" | grep -qi "Fg" && HAS_FG="true"
        echo "$ALL_XML" | grep -qi "Fn" && HAS_FN="true"
        echo "$ALL_XML" | grep -qi "Ff" && HAS_FF="true"
        echo "$ALL_XML" | grep -qi "Fnet" && HAS_FNET="true"
        
        # Check Shapes
        # Triangles often appear as AsShape with specific point data or type="Triangle"
        if echo "$ALL_XML" | grep -qi 'type="Triangle"\|AsTriangle\|<Triangle'; then
            HAS_TRIANGLE="true"
        fi
        
        # Rectangles
        if echo "$ALL_XML" | grep -qi 'type="Rectangle"\|AsRectangle\|<Rectangle'; then
            HAS_RECTANGLE="true"
        fi
        
        # Check for Rotation (angle attribute != 0)
        # ActivInspire often uses 'angle="1.57"' or similar. 
        # We look for any angle attribute that is non-zero (e.g., not angle="0" or angle="0.0")
        # This is a heuristic; VLM will be the primary check for correctness.
        if echo "$ALL_XML" | grep -E 'angle="[^-0.]|angle="-' | grep -v 'angle="0"\|angle="0.0"'; then
            HAS_ROTATION="true"
        fi
    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON result
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_valid": '$FILE_VALID' == 'true',
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "page_count": $PAGE_COUNT,
    "text_content": {
        "title": '$HAS_TITLE_TEXT' == 'true',
        "newton": '$HAS_NEWTON_TEXT' == 'true',
        "rest": '$HAS_REST_TEXT' == 'true',
        "ramp": '$HAS_RAMP_TEXT' == 'true',
        "fg": '$HAS_FG' == 'true',
        "fn": '$HAS_FN' == 'true',
        "ff": '$HAS_FF' == 'true',
        "fnet": '$HAS_FNET' == 'true'
    },
    "shapes": {
        "triangle": '$HAS_TRIANGLE' == 'true',
        "rectangle": '$HAS_RECTANGLE' == 'true',
        "rotation_detected": '$HAS_ROTATION' == 'true'
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="