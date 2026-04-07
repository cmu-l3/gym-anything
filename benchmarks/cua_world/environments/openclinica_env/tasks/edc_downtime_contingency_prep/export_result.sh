#!/bin/bash
echo "=== Exporting edc_downtime_contingency_prep result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# 1. Check if CRF is in DB
CRF_EXISTS=$(oc_query "SELECT COUNT(*) FROM crf WHERE LOWER(name) LIKE '%vital signs%' AND status_id != 3" 2>/dev/null || echo "0")

# 2. Check Directory
DIR_EXISTS="false"
if [ -d "/home/ga/Documents/Downtime_Forms" ]; then
    DIR_EXISTS="true"
fi

# 3. Search for exported HTML/PDF files
SAVED_FILE=""
FILE_EXTENSION=""
FILE_SIZE="0"
CREATED_DURING_TASK="false"
EXPORTED_FILE_PATH=""

if [ "$DIR_EXISTS" = "true" ]; then
    # Find newest html or pdf
    SAVED_FILE=$(find /home/ga/Documents/Downtime_Forms -type f \( -iname "*.html" -o -iname "*.htm" -o -iname "*.pdf" \) -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$SAVED_FILE" ]; then
        FILE_EXTENSION="${SAVED_FILE##*.}"
        FILE_SIZE=$(stat -c %s "$SAVED_FILE" 2>/dev/null || echo "0")
        
        TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
        FILE_MTIME=$(stat -c %Y "$SAVED_FILE" 2>/dev/null || echo "0")
        
        if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
            CREATED_DURING_TASK="true"
        fi
        
        # Copy to tmp so it can be securely fetched by copy_from_env
        EXPORTED_FILE_PATH="/tmp/saved_crf_form.${FILE_EXTENSION}"
        cp "$SAVED_FILE" "$EXPORTED_FILE_PATH" 2>/dev/null || true
        chmod 666 "$EXPORTED_FILE_PATH" 2>/dev/null || true
    fi
fi

NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# 4. Write export to JSON
TEMP_JSON=$(mktemp /tmp/edc_downtime_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "crf_exists_in_db": $([ "${CRF_EXISTS:-0}" -gt 0 ] 2>/dev/null && echo "true" || echo "false"),
    "dir_exists": $DIR_EXISTS,
    "saved_file_found": $([ -n "$SAVED_FILE" ] && echo "true" || echo "false"),
    "file_extension": "$FILE_EXTENSION",
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "exported_file_path": "$EXPORTED_FILE_PATH",
    "result_nonce": "$NONCE"
}
EOF

# Move securely
rm -f /tmp/edc_downtime_result.json 2>/dev/null || sudo rm -f /tmp/edc_downtime_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/edc_downtime_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/edc_downtime_result.json
chmod 666 /tmp/edc_downtime_result.json 2>/dev/null || sudo chmod 666 /tmp/edc_downtime_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/edc_downtime_result.json"
cat /tmp/edc_downtime_result.json
echo "=== Export complete ==="