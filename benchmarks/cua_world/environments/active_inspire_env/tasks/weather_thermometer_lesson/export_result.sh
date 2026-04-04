#!/bin/bash
echo "=== Exporting Weather Thermometer Lesson Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
TARGET_FILE="/home/ga/Documents/Flipcharts/weather_tracker.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/weather_tracker.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Variables for verification
FILE_FOUND="false"
FILE_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"

# Text content flags
HAS_TITLE_DASHBOARD="false"
HAS_TITLE_LOG="false"
HAS_TEMP_0="false"
HAS_TEMP_32="false"
HAS_TEMP_50="false"
HAS_TEMP_70="false"
HAS_TEMP_100="false"
HAS_SUNNY="false"
HAS_RAINY="false"
HAS_MON="false"
HAS_WED="false"
HAS_FRI="false"

# Shape counts
CIRCLE_COUNT=0
RECT_COUNT=0
LINE_COUNT=0

# Check file existence
if [ -f "$TARGET_FILE" ]; then
    FILE_FOUND="true"
    FILE_PATH="$TARGET_FILE"
elif [ -f "$TARGET_FILE_ALT" ]; then
    FILE_FOUND="true"
    FILE_PATH="$TARGET_FILE_ALT"
fi

if [ "$FILE_FOUND" = "true" ]; then
    FILE_SIZE=$(get_file_size "$FILE_PATH")
    FILE_MTIME=$(get_file_mtime "$FILE_PATH")
    
    # Check timestamp (Anti-gaming)
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Check validity and page count
    if check_flipchart_file "$FILE_PATH" | grep -q "valid"; then
        FILE_VALID="true"
        PAGE_COUNT=$(get_flipchart_page_count "$FILE_PATH")
    fi

    # Extract XML content for detailed analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$FILE_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Combine all XML text for searching
        ALL_XML_TEXT=""
        for xml in "$TMP_DIR"/*.xml; do
            if [ -f "$xml" ]; then
                ALL_XML_TEXT="${ALL_XML_TEXT} $(cat "$xml")"
            fi
        done

        # Check Text Content
        echo "$ALL_XML_TEXT" | grep -qi "Today.*Weather" && HAS_TITLE_DASHBOARD="true"
        echo "$ALL_XML_TEXT" | grep -qi "Weekly Log" && HAS_TITLE_LOG="true"
        
        # Check specific numbers (word boundaries to avoid matching 100 as 0)
        echo "$ALL_XML_TEXT" | grep -q "\"0\"" && HAS_TEMP_0="true" # Look for explicit text string
        echo "$ALL_XML_TEXT" | grep -q ">0<" && HAS_TEMP_0="true"   # XML content format
        
        echo "$ALL_XML_TEXT" | grep -qi "32" && HAS_TEMP_32="true"
        echo "$ALL_XML_TEXT" | grep -qi "50" && HAS_TEMP_50="true"
        echo "$ALL_XML_TEXT" | grep -qi "70" && HAS_TEMP_70="true"
        echo "$ALL_XML_TEXT" | grep -qi "100" && HAS_TEMP_100="true"
        
        echo "$ALL_XML_TEXT" | grep -qi "Sunny" && HAS_SUNNY="true"
        echo "$ALL_XML_TEXT" | grep -qi "Rainy" && HAS_RAINY="true"
        
        echo "$ALL_XML_TEXT" | grep -qi "Mon" && HAS_MON="true"
        echo "$ALL_XML_TEXT" | grep -qi "Wed" && HAS_WED="true"
        echo "$ALL_XML_TEXT" | grep -qi "Fri" && HAS_FRI="true"

        # Check Shapes
        # Count occurrences of shape definitions in XML
        # Rectangle
        R_COUNT=$(echo "$ALL_XML_TEXT" | grep -icE 'AsRectangle|type="Rectangle"|shape="Rectangle"')
        RECT_COUNT=$((RECT_COUNT + R_COUNT))
        
        # Circle/Oval
        C_COUNT=$(echo "$ALL_XML_TEXT" | grep -icE 'AsCircle|AsEllipse|type="Circle"|type="Ellipse"')
        CIRCLE_COUNT=$((CIRCLE_COUNT + C_COUNT))

        # Line
        L_COUNT=$(echo "$ALL_XML_TEXT" | grep -icE 'AsLine|type="Line"')
        LINE_COUNT=$((LINE_COUNT + L_COUNT))
        
        rm -rf "$TMP_DIR"
    fi
fi

# Create JSON result
# Using python for safe JSON generation
python3 << EOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_valid": $FILE_VALID,
    "created_during_task": $CREATED_DURING_TASK,
    "page_count": $PAGE_COUNT,
    "file_size": $FILE_SIZE,
    "text_content": {
        "dashboard_title": $HAS_TITLE_DASHBOARD,
        "weekly_log_title": $HAS_TITLE_LOG,
        "temp_0": $HAS_TEMP_0,
        "temp_32": $HAS_TEMP_32,
        "temp_50": $HAS_TEMP_50,
        "temp_70": $HAS_TEMP_70,
        "temp_100": $HAS_TEMP_100,
        "sunny": $HAS_SUNNY,
        "rainy": $HAS_RAINY,
        "mon": $HAS_MON,
        "wed": $HAS_WED,
        "fri": $HAS_FRI
    },
    "shapes": {
        "rect_count": $RECT_COUNT,
        "circle_count": $CIRCLE_COUNT,
        "line_count": $LINE_COUNT
    },
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="