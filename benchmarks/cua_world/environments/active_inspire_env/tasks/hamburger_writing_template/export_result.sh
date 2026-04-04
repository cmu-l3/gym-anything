#!/bin/bash
# Export script for Hamburger Writing Template task
echo "=== Exporting Hamburger Writing Template Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Target paths
FILE_PATH="/home/ga/Documents/Flipcharts/hamburger_paragraph.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/hamburger_paragraph.flp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"

# Content flags
HAS_TITLE="false"
HAS_TOPIC="false"
HAS_CONCLUSION="false"
HAS_DETAIL1="false"
HAS_DETAIL2="false"
HAS_DETAIL3="false"
HAS_PRACTICE_TITLE="false"

# Element counts
SHAPE_COUNT=0
LINE_COUNT=0

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

    # Check validity
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check timestamp
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Deep content analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # 1. Text Analysis
        # Concatenate all XML text for searching
        ALL_XML_TEXT=""
        for xml in "$TMP_DIR"/*.xml; do
            [ -f "$xml" ] && ALL_XML_TEXT="$ALL_XML_TEXT $(cat "$xml")"
        done

        # Check for required text strings (case insensitive)
        echo "$ALL_XML_TEXT" | grep -qi "Hamburger Paragraph" && HAS_TITLE="true"
        echo "$ALL_XML_TEXT" | grep -qi "Topic Sentence" && HAS_TOPIC="true"
        echo "$ALL_XML_TEXT" | grep -qi "Conclusion" && HAS_CONCLUSION="true"
        echo "$ALL_XML_TEXT" | grep -qi "Detail 1" && HAS_DETAIL1="true"
        echo "$ALL_XML_TEXT" | grep -qi "Detail 2" && HAS_DETAIL2="true"
        echo "$ALL_XML_TEXT" | grep -qi "Detail 3" && HAS_DETAIL3="true"
        echo "$ALL_XML_TEXT" | grep -qi "My Paragraph" && HAS_PRACTICE_TITLE="true"

        # 2. Shape Analysis (for the Burger)
        # Look for AsShape, AsRectangle, AsEllipse, AsOval or type="Rectangle"/"Ellipse"
        # We want to find actual geometric shapes, not just text boxes (which are technically shapes too in some schemas)
        # ActivInspire often uses <AsShape ... shapeType="Rectangle">
        SHAPE_COUNT=$(grep -oE '(<AsRectangle|<AsEllipse|<AsOval|shapeType="Rectangle"|shapeType="Ellipse"|shapeType="Circle"|type="Rectangle"|type="Ellipse")' "$TMP_DIR"/*.xml 2>/dev/null | wc -l)

        # 3. Line Analysis (for the writing lines)
        # Look for AsLine, AsConnector, AsPolyLine
        LINE_COUNT=$(grep -oE '(<AsLine|<AsConnector|<AsPolyLine|type="Line"|type="Connector")' "$TMP_DIR"/*.xml 2>/dev/null | wc -l)

    fi
    rm -rf "$TMP_DIR"
fi

# Create result JSON using Python
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
    "text_content": {
        "has_title": $HAS_TITLE,
        "has_topic": $HAS_TOPIC,
        "has_conclusion": $HAS_CONCLUSION,
        "has_detail1": $HAS_DETAIL1,
        "has_detail2": $HAS_DETAIL2,
        "has_detail3": $HAS_DETAIL3,
        "has_practice_title": $HAS_PRACTICE_TITLE
    },
    "shape_count": $SHAPE_COUNT,
    "line_count": $LINE_COUNT,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Result JSON generated."
cat /tmp/task_result.json
echo "=== Export Complete ==="