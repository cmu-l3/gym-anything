#!/bin/bash
echo "=== Exporting install_custom_citation_style results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check output file
OUTPUT_FILE="/home/ga/Documents/bibliography.rtf"
OUTPUT_EXISTS="false"
MARKER_FOUND="false"
AUTHORS_FOUND=0
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    
    # Check for the unique style marker [JAA]
    # RTF escapes might make exact matching tricky, but usually plain text passes through
    # or is slightly escaped. grep -a treats binary as text.
    if grep -a "\[JAA\]" "$OUTPUT_FILE" > /dev/null; then
        MARKER_FOUND="true"
    fi
    
    # Check for target authors
    # LeCun
    if grep -a "LeCun" "$OUTPUT_FILE" > /dev/null; then
        AUTHORS_FOUND=$((AUTHORS_FOUND + 1))
    fi
    # Vaswani
    if grep -a "Vaswani" "$OUTPUT_FILE" > /dev/null; then
        AUTHORS_FOUND=$((AUTHORS_FOUND + 1))
    fi
    # Goodfellow
    if grep -a "Goodfellow" "$OUTPUT_FILE" > /dev/null; then
        AUTHORS_FOUND=$((AUTHORS_FOUND + 1))
    fi
fi

# 3. Check if style file is installed in profile
STYLE_INSTALLED="false"
PROFILE_DIR=$(find /home/ga/.zotero/zotero -maxdepth 1 -type d -name "*.default" | head -n 1)
INSTALLED_STYLE_PATH=""

if [ -n "$PROFILE_DIR" ]; then
    # Zotero usually renames the file to the <id> in the CSL, or keeps filename
    # Our ID is journal-of-applied-ai, so we expect journal-of-applied-ai.csl
    if [ -f "$PROFILE_DIR/styles/journal-of-applied-ai.csl" ]; then
        STYLE_INSTALLED="true"
        INSTALLED_STYLE_PATH="$PROFILE_DIR/styles/journal-of-applied-ai.csl"
    fi
fi

# 4. Anti-gaming: Check file modification time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "marker_found": $MARKER_FOUND,
    "authors_found_count": $AUTHORS_FOUND,
    "style_installed": $STYLE_INSTALLED,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "installed_style_path": "$INSTALLED_STYLE_PATH"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="