#!/bin/bash
echo "=== Exporting WWI Fishbone Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Parameters
FILE_PATH="/home/ga/Documents/Flipcharts/ww1_fishbone.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/ww1_fishbone.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
CREATED_DURING_TASK="false"

# Content counters
LINE_COUNT=0
SHAPE_COUNT=0
TEXT_MILITARISM="false"
TEXT_ALLIANCES="false"
TEXT_IMPERIALISM="false"
TEXT_NATIONALISM="false"
TEXT_WWI="false"
TEXT_TITLE="false"

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
    
    # Check validity (zip format)
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check timestamp
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Analyze content by extracting ZIP
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Combine all XML content for searching
        # ActivInspire stores page content in page*.xml files usually
        ALL_XML_CONTENT=""
        for xml in "$TMP_DIR"/*.xml; do
            if [ -f "$xml" ]; then
                ALL_XML_CONTENT="${ALL_XML_CONTENT} $(cat "$xml")"
            fi
        done
        
        # Count Lines (looking for line objects)
        # Patterns: AsLine, LineShape, type="Line"
        LINE_COUNT=$(echo "$ALL_XML_CONTENT" | grep -oE '<AsLine|<LineShape|type="Line"' | wc -l)
        
        # Count Shapes (looking for heads/boxes)
        # Patterns: AsShape, AsRectangle, AsCircle, AsTriangle, type="Shape"
        SHAPE_COUNT=$(echo "$ALL_XML_CONTENT" | grep -oE '<AsShape|<AsRectangle|<AsCircle|<AsTriangle|type="Shape"' | wc -l)

        # Check Text Content (case insensitive)
        if echo "$ALL_XML_CONTENT" | grep -qi "Militarism"; then TEXT_MILITARISM="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qi "Alliances"; then TEXT_ALLIANCES="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qi "Imperialism"; then TEXT_IMPERIALISM="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qi "Nationalism"; then TEXT_NATIONALISM="true"; fi
        
        # Check Head Label (WWI or War)
        if echo "$ALL_XML_CONTENT" | grep -qi "WWI\|World War\|The War"; then TEXT_WWI="true"; fi
        
        # Check Title (Causes)
        if echo "$ALL_XML_CONTENT" | grep -qi "Causes"; then TEXT_TITLE="true"; fi

    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON result safely
create_result_json << EOF
{
    "file_found": $(json_bool "$FILE_FOUND"),
    "file_valid": $(json_bool "$FILE_VALID"),
    "created_during_task": $(json_bool "$CREATED_DURING_TASK"),
    "line_count": $LINE_COUNT,
    "shape_count": $SHAPE_COUNT,
    "text_militarism": $(json_bool "$TEXT_MILITARISM"),
    "text_alliances": $(json_bool "$TEXT_ALLIANCES"),
    "text_imperialism": $(json_bool "$TEXT_IMPERIALISM"),
    "text_nationalism": $(json_bool "$TEXT_NATIONALISM"),
    "text_wwi": $(json_bool "$TEXT_WWI"),
    "text_title": $(json_bool "$TEXT_TITLE"),
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="