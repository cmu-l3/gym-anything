#!/bin/bash
# Export script for Geometry Exit Ticket task
# Analyzes the flipchart file structure and content

echo "=== Exporting Geometry Exit Ticket Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Paths
FILE_PATH="/home/ga/Documents/Flipcharts/geometry_exit_ticket.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/geometry_exit_ticket.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"

# Content flags
HAS_TITLE_TEXT="false"      # "Exit Ticket"
HAS_TEACHER_NAME="false"    # "Rivera"
HAS_ACUTE="false"
HAS_RIGHT="false"
HAS_OBTUSE="false"
HAS_SELF_ASSESS="false"     # "How did you do" / "Got it" etc.

# Shape counts
LINE_COUNT=0       # For angles (AsLine, AsPolyline, AsConnector)
CIRCLE_COUNT=0     # For self-assessment (AsCircle, AsEllipse)

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

    # Check validity (flipchart is a ZIP)
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check timestamp
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Analyze Content
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # 1. Aggregate all text content from XMLs
        ALL_TEXT=""
        # ActivInspire stores page content in page*.xml or similar
        # Find all xml files
        XML_FILES=$(find "$TMP_DIR" -name "*.xml" -type f)
        
        for xml in $XML_FILES; do
             # Simple extraction of everything that looks like text
             # (ActivInspire XML can be complex, raw grep is usually sufficient for existence checks)
             ALL_TEXT="$ALL_TEXT $(cat "$xml")"
        done

        # Check Text Requirements
        if echo "$ALL_TEXT" | grep -qi "Exit Ticket"; then HAS_TITLE_TEXT="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Rivera"; then HAS_TEACHER_NAME="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Acute"; then HAS_ACUTE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Right"; then HAS_RIGHT="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Obtuse"; then HAS_OBTUSE="true"; fi
        if echo "$ALL_TEXT" | grep -qiE "How did you do|Got it|Almost|Help|Self.*Check"; then HAS_SELF_ASSESS="true"; fi

        # 2. Count Shapes in XMLs
        # Lines for angles
        # Look for: AsLine, AsPolyline, AsConnector, type="Line", etc.
        # Note: grep -c counts lines, but multiple shapes might be on one line if minified, 
        # though usually pretty printed. grep -o | wc -l is safer.
        LINE_MATCHES=$(grep -oEi 'AsLine|AsPolyline|AsConnector|type="Line"|shapeType="Line"' $XML_FILES 2>/dev/null | wc -l)
        LINE_COUNT=$LINE_MATCHES

        # Circles for self assessment
        # Look for: AsCircle, AsEllipse, AsOval
        CIRCLE_MATCHES=$(grep -oEi 'AsCircle|AsEllipse|AsOval|type="Circle"|type="Ellipse"|shapeType="Circle"|shapeType="Ellipse"' $XML_FILES 2>/dev/null | wc -l)
        CIRCLE_COUNT=$CIRCLE_MATCHES
        
    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON Result
python3 << PYEOF
import json
import os

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_valid": $FILE_VALID,
    "created_during_task": $CREATED_DURING_TASK,
    "page_count": $PAGE_COUNT,
    "has_title_text": $HAS_TITLE_TEXT,
    "has_teacher_name": $HAS_TEACHER_NAME,
    "has_acute": $HAS_ACUTE,
    "has_right": $HAS_RIGHT,
    "has_obtuse": $HAS_OBTUSE,
    "has_self_assess": $HAS_SELF_ASSESS,
    "line_count": $LINE_COUNT,
    "circle_count": $CIRCLE_COUNT,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="