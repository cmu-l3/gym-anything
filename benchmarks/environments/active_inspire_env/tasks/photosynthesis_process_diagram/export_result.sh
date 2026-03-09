#!/bin/bash
echo "=== Exporting Photosynthesis Diagram Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
FILE_PATH="/home/ga/Documents/Flipcharts/photosynthesis_lesson.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/photosynthesis_lesson.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Initialize variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
FILE_SIZE=0

# Content flags
HAS_TITLE="false"
HAS_DEF="false"
HAS_CO2="false"
HAS_WATER="false"
HAS_SUNLIGHT="false"
HAS_OXYGEN="false"
HAS_GLUCOSE="false"
HAS_SUN_SHAPE="false"
HAS_ARROWS="false"

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
    
    # Check if created during task
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Check validity and parse content
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
        PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")
        
        # Extract XML content for analysis
        TMP_DIR=$(mktemp -d)
        if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
            # Concatenate all XML text for searching
            ALL_TEXT=$(grep -r "" "$TMP_DIR" --include="*.xml" 2>/dev/null)
            
            # Text Checks (Case Insensitive)
            if echo "$ALL_TEXT" | grep -qi "Photosynthesis"; then HAS_TITLE="true"; fi
            if echo "$ALL_TEXT" | grep -qi "make.*food"; then HAS_DEF="true"; fi
            if echo "$ALL_TEXT" | grep -qiE "Carbon\s*Dioxide|CO2"; then HAS_CO2="true"; fi
            if echo "$ALL_TEXT" | grep -qiE "Water|H2O"; then HAS_WATER="true"; fi
            if echo "$ALL_TEXT" | grep -qi "Sunlight"; then HAS_SUNLIGHT="true"; fi
            if echo "$ALL_TEXT" | grep -qiE "Oxygen|O2"; then HAS_OXYGEN="true"; fi
            if echo "$ALL_TEXT" | grep -qiE "Glucose|Sugar"; then HAS_GLUCOSE="true"; fi
            
            # Shape Checks
            # Look for Circle/Ellipse/Oval shapes (Sun)
            if echo "$ALL_TEXT" | grep -qiE "AsCircle|AsEllipse|AsOval|type=\"Circle\"|type=\"Ellipse\""; then 
                HAS_SUN_SHAPE="true"
            fi
            
            # Look for Arrows or Lines
            if echo "$ALL_TEXT" | grep -qiE "AsArrow|AsLine|type=\"Arrow\"|type=\"Line\"|shape=\"Arrow\""; then
                HAS_ARROWS="true"
            fi
            
            rm -rf "$TMP_DIR"
        fi
    fi
fi

# Create JSON result
# Using python for safe JSON generation
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_valid": $FILE_VALID,
    "created_during_task": $CREATED_DURING_TASK,
    "page_count": $PAGE_COUNT,
    "file_size": $FILE_SIZE,
    "content": {
        "has_title": $HAS_TITLE,
        "has_definition": $HAS_DEF,
        "has_co2": $HAS_CO2,
        "has_water": $HAS_WATER,
        "has_sunlight": $HAS_SUNLIGHT,
        "has_oxygen": $HAS_OXYGEN,
        "has_glucose": $HAS_GLUCOSE,
        "has_sun_shape": $HAS_SUN_SHAPE,
        "has_arrows": $HAS_ARROWS
    },
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="