#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_DIR="/home/ga/Documents/ProfileBackup"

# Find the ZIP file
ZIP_FILE=$(find "$TARGET_DIR" -maxdepth 1 -name "*.zip" -type f | head -1)

ZIP_EXISTS="false"
ZIP_CREATED_DURING_TASK="false"
ZIP_SIZE="0"
ZIP_VALID="false"
HAS_PREFS="false"
HAS_MAIL="false"
ZIP_BASENAME=""

if [ -n "$ZIP_FILE" ] && [ -f "$ZIP_FILE" ]; then
    ZIP_EXISTS="true"
    ZIP_BASENAME=$(basename "$ZIP_FILE")
    ZIP_SIZE=$(stat -c %s "$ZIP_FILE" 2>/dev/null || echo "0")
    ZIP_MTIME=$(stat -c %Y "$ZIP_FILE" 2>/dev/null || echo "0")
    
    if [ "$ZIP_MTIME" -ge "$TASK_START" ]; then
        ZIP_CREATED_DURING_TASK="true"
    fi

    # Inspect the ZIP file using Python to avoid copying large files to the host machine
    ZIP_INFO=$(python3 -c "
import zipfile, json, sys
try:
    with zipfile.ZipFile('$ZIP_FILE', 'r') as z:
        namelist = z.namelist()
        has_prefs = any('prefs.js' in n for n in namelist)
        has_mail = any('Mail' in n for n in namelist)
        print(json.dumps({
            'valid': True, 
            'has_prefs': has_prefs, 
            'has_mail': has_mail,
            'file_count': len(namelist)
        }))
except Exception as e:
    print(json.dumps({'valid': False, 'error': str(e), 'has_prefs': False, 'has_mail': False, 'file_count': 0}))
" 2>/dev/null || echo '{"valid": false, "has_prefs": false, "has_mail": false, "file_count": 0}')
    
    # Safely parse JSON properties out in shell
    ZIP_VALID=$(echo "$ZIP_INFO" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('valid', False)).lower())")
    HAS_PREFS=$(echo "$ZIP_INFO" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('has_prefs', False)).lower())")
    HAS_MAIL=$(echo "$ZIP_INFO" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('has_mail', False)).lower())")
fi

# Generate the result JSON via a secure temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "zip_exists": $ZIP_EXISTS,
    "zip_filename": "$ZIP_BASENAME",
    "zip_created_during_task": $ZIP_CREATED_DURING_TASK,
    "zip_size_bytes": $ZIP_SIZE,
    "zip_valid": $ZIP_VALID,
    "has_prefs": $HAS_PREFS,
    "has_mail": $HAS_MAIL,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Copy the result to the expected final destination
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="