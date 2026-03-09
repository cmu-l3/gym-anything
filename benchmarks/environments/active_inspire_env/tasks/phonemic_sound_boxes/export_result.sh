#!/bin/bash
echo "=== Exporting Phonemic Sound Boxes Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_end.png
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 2. Define Expected Output
FILE_PATH="/home/ga/Documents/Flipcharts/phonemic_awareness.flipchart"
# ActivInspire sometimes uses .flp for older formats, check both
if [ ! -f "$FILE_PATH" ]; then
    FILE_PATH="/home/ga/Documents/Flipcharts/phonemic_awareness.flp"
fi

# 3. Analyze File Content
FILE_FOUND="false"
FILE_VALID="false"
CREATED_DURING_TASK="false"
HAS_SOUND_BOXES_TEXT="false"
RECT_COUNT=0
CIRCLE_COUNT=0
IMAGE_COUNT=0
RED_COLOR_FOUND="false"

if [ -f "$FILE_PATH" ]; then
    FILE_FOUND="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$FILE_PATH")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Check validity and unzip for analysis
    # Flipcharts are ZIPs containing XMLs
    TMP_DIR=$(mktemp -d)
    if unzip -q "$FILE_PATH" -d "$TMP_DIR" 2>/dev/null; then
        FILE_VALID="true"
        
        # Concatenate all XML content for searching
        ALL_XML=$(cat "$TMP_DIR"/*.xml 2>/dev/null)
        
        # Check for Title
        if echo "$ALL_XML" | grep -qi "Sound Boxes"; then
            HAS_SOUND_BOXES_TEXT="true"
        fi
        
        # Count Shapes (Rectangles for boxes)
        # Looking for AsRectangle or type="Rectangle"
        RECT_COUNT=$(echo "$ALL_XML" | grep -oEi 'AsRectangle|type="Rectangle"' | wc -l)
        
        # Count Shapes (Circles for counters)
        # Looking for AsEllipse, AsCircle, or type="Ellipse"
        CIRCLE_COUNT=$(echo "$ALL_XML" | grep -oEi 'AsEllipse|AsCircle|type="Ellipse"|type="Circle"' | wc -l)
        
        # Check for Images
        # Images usually stored in specific folders or referenced in XML
        # Count distinct image resources inside the zip
        IMAGE_COUNT=$(find "$TMP_DIR" -type f -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" | wc -l)
        
        # Check for Red Color (approximate check in XML attributes)
        # ActivInspire stores colors often as integers or hex
        # Checking for "Red" might be unreliable in raw XML without parsing, 
        # but we can look for common attribute values if known. 
        # We will rely more on VLM for color verification, but flag if we see color attributes.
        # This is a weak signal, so we set it to true if we see ANY color definitions typically associated with shapes.
        if echo "$ALL_XML" | grep -qi "color"; then
             RED_COLOR_FOUND="maybe" 
        fi
        
    fi
    rm -rf "$TMP_DIR"
fi

# 4. Generate JSON Result
# Using python for safe JSON generation
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$FILE_PATH",
    "file_valid": $FILE_VALID,
    "created_during_task": $CREATED_DURING_TASK,
    "has_title_text": $HAS_SOUND_BOXES_TEXT,
    "rect_count": $RECT_COUNT,
    "circle_count": $CIRCLE_COUNT,
    "image_count": $IMAGE_COUNT,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="