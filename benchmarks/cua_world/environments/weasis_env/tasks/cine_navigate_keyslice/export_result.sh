#!/bin/bash
echo "=== Exporting cine_navigate_keyslice task result ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

take_screenshot /tmp/task_final.png

EXPORT_DIR="/home/ga/DICOM/exports"
PNG_FILE="$EXPORT_DIR/key_slice.png"
TXT_FILE="$EXPORT_DIR/slice_info.txt"

PNG_EXISTS="false"
PNG_MTIME="0"
PNG_SIZE="0"
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_MTIME=$(stat -c %Y "$PNG_FILE" 2>/dev/null || echo "0")
    PNG_SIZE=$(stat -c %s "$PNG_FILE" 2>/dev/null || echo "0")
fi

TXT_EXISTS="false"
TXT_MTIME="0"
TXT_SIZE="0"
if [ -f "$TXT_FILE" ]; then
    TXT_EXISTS="true"
    TXT_MTIME=$(stat -c %Y "$TXT_FILE" 2>/dev/null || echo "0")
    TXT_SIZE=$(stat -c %s "$TXT_FILE" 2>/dev/null || echo "0")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "png_exists": $PNG_EXISTS,
    "png_mtime": $PNG_MTIME,
    "png_size": $PNG_SIZE,
    "txt_exists": $TXT_EXISTS,
    "txt_mtime": $TXT_MTIME,
    "txt_size": $TXT_SIZE
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="