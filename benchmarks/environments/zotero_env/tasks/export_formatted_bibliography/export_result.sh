#!/bin/bash
echo "=== Exporting task results ==="

# Define paths
OUTPUT_FILE="/home/ga/Documents/thesis_chapter3_references.html"
RESULT_JSON="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Initialize variables
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED=0
FILE_CREATED_DURING_TASK="false"
HAS_HTML_TAGS="false"
ENTRY_COUNT=0
CONTENT_CHECK_SHANNON="false"
CONTENT_CHECK_TURING="false"
CONTENT_CHECK_VASWANI="false"
CONTENT_CHECK_LECUN="false"
CONTENT_CHECK_RESNET="false"

# Check file status
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MODIFIED=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if modified after start
    if [ "$FILE_MODIFIED" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Read content for analysis
    # Convert to lowercase for case-insensitive matching
    CONTENT=$(cat "$OUTPUT_FILE" | tr '[:upper:]' '[:lower:]')

    # check for HTML tags (simple heuristic)
    if echo "$CONTENT" | grep -q "<div\|<span\|<p\|<html\|<body"; then
        HAS_HTML_TAGS="true"
    fi

    # Count entries (APA bibliography usually wraps entries in div or p with hanging indent)
    # We count occurrences of common author names or years to estimate entries
    # Or count specific HTML classes if Zotero uses them (csl-entry)
    ENTRY_COUNT=$(grep -o "csl-entry" "$OUTPUT_FILE" | wc -l)
    if [ "$ENTRY_COUNT" -eq 0 ]; then
        # Fallback: count lines that look like references (year in parens)
        ENTRY_COUNT=$(grep -c "([0-9]\{4\})" "$OUTPUT_FILE")
    fi

    # Check for specific content (using grep on original file to be safe or cached content)
    if echo "$CONTENT" | grep -q "shannon"; then CONTENT_CHECK_SHANNON="true"; fi
    if echo "$CONTENT" | grep -q "turing"; then CONTENT_CHECK_TURING="true"; fi
    if echo "$CONTENT" | grep -q "vaswani"; then CONTENT_CHECK_VASWANI="true"; fi
    if echo "$CONTENT" | grep -q "lecun"; then CONTENT_CHECK_LECUN="true"; fi
    if echo "$CONTENT" | grep -q "deep residual learning"; then CONTENT_CHECK_RESNET="true"; fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Write JSON result
# Use python for robust JSON creation
python3 <<EOF
import json
import os

result = {
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "has_html_tags": $HAS_HTML_TAGS,
    "entry_count": $ENTRY_COUNT,
    "content_check": {
        "shannon": $CONTENT_CHECK_SHANNON,
        "turing": $CONTENT_CHECK_TURING,
        "vaswani": $CONTENT_CHECK_VASWANI,
        "lecun": $CONTENT_CHECK_LECUN,
        "resnet": $CONTENT_CHECK_RESNET
    }
}

with open("$RESULT_JSON", "w") as f:
    json.dump(result, f)
EOF

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="