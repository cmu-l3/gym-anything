#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/info_theory_foundations.bib"

# Initialize variables
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
ENTRY_COUNT="0"
CONTENT_SHANNON="false"
CONTENT_HUFFMAN="false"
CONTENT_TURING="false"
IS_BIBTEX="false"

# Check file existence and attributes
if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check for BibTeX format (look for @article, @misc, etc.)
    if grep -qE "^@" "$OUTPUT_PATH"; then
        IS_BIBTEX="true"
    fi

    # Count entries (lines starting with @)
    ENTRY_COUNT=$(grep -cE "^@" "$OUTPUT_PATH" 2>/dev/null || echo "0")

    # Check for content keywords
    if grep -qi "Shannon" "$OUTPUT_PATH" && grep -qi "Mathematical Theory" "$OUTPUT_PATH"; then
        CONTENT_SHANNON="true"
    fi
    if grep -qi "Huffman" "$OUTPUT_PATH" && grep -qi "Redundancy" "$OUTPUT_PATH"; then
        CONTENT_HUFFMAN="true"
    fi
    if grep -qi "Turing" "$OUTPUT_PATH" && grep -qi "Computable" "$OUTPUT_PATH"; then
        CONTENT_TURING="true"
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "is_bibtex": $IS_BIBTEX,
    "entry_count": $ENTRY_COUNT,
    "contains_shannon": $CONTENT_SHANNON,
    "contains_huffman": $CONTENT_HUFFMAN,
    "contains_turing": $CONTENT_TURING
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="