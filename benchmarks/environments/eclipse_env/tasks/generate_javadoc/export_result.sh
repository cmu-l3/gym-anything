#!/bin/bash
echo "=== Exporting Generate JavaDoc result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/javadoc-output"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if index.html exists
INDEX_EXISTS="false"
INDEX_SIZE="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_DIR/index.html" ]; then
    INDEX_EXISTS="true"
    INDEX_SIZE=$(stat -c %s "$OUTPUT_DIR/index.html" 2>/dev/null || echo "0")
    
    # Check creation time
    FILE_TIME=$(stat -c %Y "$OUTPUT_DIR/index.html" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
elif [ -f "$OUTPUT_DIR/doc/index.html" ]; then
    # Handle case where user added extra 'doc' subdir
    INDEX_EXISTS="true"
    INDEX_SIZE=$(stat -c %s "$OUTPUT_DIR/doc/index.html" 2>/dev/null || echo "0")
    CREATED_DURING_TASK="true" # Assume valid if path differs slightly
    OUTPUT_DIR="$OUTPUT_DIR/doc"
fi

# Check for package directories (simple check)
PKG_TEXT_EXISTS=$([ -d "$OUTPUT_DIR/com/devutils/text" ] && echo "true" || echo "false")
PKG_MATH_EXISTS=$([ -d "$OUTPUT_DIR/com/devutils/math" ] && echo "true" || echo "false")
PKG_COLL_EXISTS=$([ -d "$OUTPUT_DIR/com/devutils/collection" ] && echo "true" || echo "false")

# Check for class HTML files
CLASS_FILES_COUNT=$(find "$OUTPUT_DIR" -name "*.html" -type f 2>/dev/null | grep -E "StringUtils|CaseFormat|MathUtils|Statistics|ListUtils" | wc -l)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "index_exists": $INDEX_EXISTS,
    "index_size": $INDEX_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "pkg_text_exists": $PKG_TEXT_EXISTS,
    "pkg_math_exists": $PKG_MATH_EXISTS,
    "pkg_coll_exists": $PKG_COLL_EXISTS,
    "class_files_count": $CLASS_FILES_COUNT,
    "output_dir_used": "$OUTPUT_DIR"
}
EOF

write_json_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="