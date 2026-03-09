#!/bin/bash
echo "=== Exporting add_text_annotation task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Check for expected file
EXPECTED_FILE="/home/ga/Documents/Flipcharts/lesson_with_text.flipchart"
EXPECTED_FILE_ALT="/home/ga/Documents/Flipcharts/lesson_with_text.flp"

FILE_FOUND="false"
FILE_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_TYPE=""
FILE_VALID="false"
TEXT_FOUND="false"
EXPECTED_TEXT="Welcome to Today's Lesson"

# Check primary expected path
if [ -f "$EXPECTED_FILE" ]; then
    FILE_FOUND="true"
    FILE_PATH="$EXPECTED_FILE"
elif [ -f "$EXPECTED_FILE_ALT" ]; then
    FILE_FOUND="true"
    FILE_PATH="$EXPECTED_FILE_ALT"
fi

# If found, gather file info
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

    # Try to find the expected text in the flipchart content XML
    # Flipchart files are ZIP archives containing XML
    # We search only in XML files to avoid matching metadata, thumbnails, or other embedded content
    TEMP_DIR=$(mktemp -d)
    if unzip -q "$FILE_PATH" -d "$TEMP_DIR" 2>/dev/null; then
        # Search for text ONLY in XML files (content.xml, page*.xml, etc.)
        # This avoids false positives from metadata, thumbnails, or embedded resources
        # Look for text within text elements: <text>, <AsText>, <TextAnnotation>, etc.
        # or as CDATA content in text containers

        # Find all XML files in the extracted content
        XML_FILES=$(find "$TEMP_DIR" -name "*.xml" -type f 2>/dev/null)

        if [ -n "$XML_FILES" ]; then
            # Search for the expected text phrase in text content elements
            # Match text inside XML text elements or as element content
            if echo "$XML_FILES" | xargs grep -qi "Welcome to Today" 2>/dev/null; then
                TEXT_FOUND="true"
            elif echo "$XML_FILES" | xargs grep -qi "Welcome" 2>/dev/null && \
                 echo "$XML_FILES" | xargs grep -qi "Lesson" 2>/dev/null; then
                # Partial match - both words present but not necessarily together
                TEXT_FOUND="partial"
            fi
        fi
    fi
    rm -rf "$TEMP_DIR"
else
    CREATED_DURING_TASK="false"
fi

# List all flipchart files for debugging
ALL_FLIPCHARTS=$(list_flipcharts /home/ga/Documents/Flipcharts | tr '\n' ',' | sed 's/,$//')

# Create JSON result with properly typed values
# Use json_bool for boolean values, keep text_found as string since it can be "partial"
create_result_json << EOF
{
    "file_found": $(json_bool "$FILE_FOUND"),
    "file_path": "$FILE_PATH",
    "file_size": ${FILE_SIZE:-0},
    "file_mtime": ${FILE_MTIME:-0},
    "file_type": "$FILE_TYPE",
    "file_valid": $(json_bool "$FILE_VALID"),
    "text_found": "$TEXT_FOUND",
    "expected_text": "$EXPECTED_TEXT",
    "created_during_task": $(json_bool "$CREATED_DURING_TASK"),
    "all_flipcharts": "$ALL_FLIPCHARTS",
    "expected_path": "$EXPECTED_FILE",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
