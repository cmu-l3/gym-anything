#!/bin/bash
echo "=== Exporting export_key_images task result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Gather File Data
EXPORT_DIR="/home/ga/DICOM/exports/key_images"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use find to locate all jpeg/jpg files, counting them
FILE_LIST=$(find "$EXPORT_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null)
FILE_COUNT=$(echo "$FILE_LIST" | grep -v '^$' | wc -l || echo "0")

ALL_FILES_VALID_SIZE="true"
ALL_FILES_AFTER_START="true"
FILE_DATA="[]"

if [ "$FILE_COUNT" -gt 0 ]; then
    FILE_DATA="["
    FIRST="true"
    
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            SIZE=$(stat -c %s "$file" 2>/dev/null || echo "0")
            MTIME=$(stat -c %Y "$file" 2>/dev/null || echo "0")
            
            # Check size condition (>10KB expected for an exported CT slice)
            if [ "$SIZE" -lt 10000 ]; then
                ALL_FILES_VALID_SIZE="false"
            fi
            
            # Check timestamp condition (anti-gaming)
            if [ "$MTIME" -le "$TASK_START_TIME" ]; then
                ALL_FILES_AFTER_START="false"
            fi
            
            if [ "$FIRST" = "true" ]; then
                FIRST="false"
            else
                FILE_DATA="$FILE_DATA,"
            fi
            
            FILE_DATA="$FILE_DATA{\"name\": \"$(basename "$file")\", \"size\": $SIZE, \"mtime\": $MTIME}"
        fi
    done <<< "$FILE_LIST"
    
    FILE_DATA="$FILE_DATA]"
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "export_dir_exists": $([ -d "$EXPORT_DIR" ] && echo "true" || echo "false"),
    "file_count": $FILE_COUNT,
    "all_files_valid_size": $ALL_FILES_VALID_SIZE,
    "all_files_after_start": $ALL_FILES_AFTER_START,
    "files": $FILE_DATA,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="