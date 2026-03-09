#!/bin/bash
# Export script for Civil Rights Timeline task
# Analyzes the created flipchart file for content and structure

echo "=== Exporting Civil Rights Timeline Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
FILE_PATH="/home/ga/Documents/Flipcharts/civil_rights_timeline.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/civil_rights_timeline.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
CREATED_DURING_TASK="false"
PAGE_COUNT=0

# Content Analysis Variables
HAS_TITLE="false"
HAS_DATE_RANGE="false"
HAS_EVENT_BROWN="false"
HAS_EVENT_MONTGOMERY="false"
HAS_EVENT_MARCH="false"
HAS_EVENT_CRA="false"
HAS_EVENT_VRA="false"
HAS_LINE="false"
SHAPE_COUNT=0

# 1. Check if file exists
if [ -f "$FILE_PATH" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH"
elif [ -f "$FILE_PATH_ALT" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH_ALT"
fi

# 2. Analyze File Content
if [ "$FILE_FOUND" = "true" ]; then
    FILE_SIZE=$(get_file_size "$ACTUAL_PATH")
    FILE_MTIME=$(get_file_mtime "$ACTUAL_PATH")

    # Check validity (zip/xml structure)
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check timestamp
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Check page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract and grep content
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Concatenate all XML text for content searching
        # Note: In a rigorous check we might separate pages, but for this task 
        # finding the text anywhere in the doc is a good primary signal.
        # Structure checks (lines/shapes) need to be more specific if possible.
        
        ALL_XML_CONTENT=$(find "$TMP_DIR" -name "*.xml" -exec cat {} \;)
        
        # -- Text Content Checks --
        # Title components
        if echo "$ALL_XML_CONTENT" | grep -qi "Civil Rights"; then HAS_TITLE="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -q "1954" && echo "$ALL_XML_CONTENT" | grep -q "1968"; then HAS_DATE_RANGE="true"; fi
        
        # Event Checks (Case insensitive partial matches)
        if echo "$ALL_XML_CONTENT" | grep -qi "Brown"; then HAS_EVENT_BROWN="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qiE "Montgomery|Bus Boycott"; then HAS_EVENT_MONTGOMERY="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qi "March on Washington"; then HAS_EVENT_MARCH="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qi "Civil Rights Act"; then HAS_EVENT_CRA="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qi "Voting Rights Act"; then HAS_EVENT_VRA="true"; fi

        # -- Structure/Shape Checks --
        # Look for Line elements (AsLine, AsConnector, or type="Line")
        if echo "$ALL_XML_CONTENT" | grep -qiE "AsLine|AsConnector|type=\"Line\"|shapeType=\"Line\""; then
            HAS_LINE="true"
        fi

        # Count Shapes (Rectangle, Circle, Ellipse, Oval)
        # We look for explicit shape definitions usually found in page.xml files
        SHAPE_MATCHES=$(echo "$ALL_XML_CONTENT" | grep -ioE "AsRectangle|AsCircle|AsEllipse|AsOval|type=\"Rectangle\"|type=\"Circle\"|type=\"Ellipse\"" | wc -l)
        SHAPE_COUNT=$SHAPE_MATCHES
        
    fi
    rm -rf "$TMP_DIR"
fi

# 3. Create JSON Result
# Using python for safe JSON generation
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_valid": $FILE_VALID,
    "created_during_task": $CREATED_DURING_TASK,
    "page_count": $PAGE_COUNT,
    "has_title": $HAS_TITLE,
    "has_date_range": $HAS_DATE_RANGE,
    "events": {
        "brown_v_board": $HAS_EVENT_BROWN,
        "montgomery": $HAS_EVENT_MONTGOMERY,
        "march_washington": $HAS_EVENT_MARCH,
        "civil_rights_act": $HAS_EVENT_CRA,
        "voting_rights_act": $HAS_EVENT_VRA
    },
    "has_line": $HAS_LINE,
    "shape_count": $SHAPE_COUNT,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="