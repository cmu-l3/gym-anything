#!/bin/bash
echo "=== Exporting task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

ED_DATA_FILE="/home/ga/Documents/ed_encounters_august.xlsx"
FILE_MODIFIED="false"
FILE_EXISTS="false"
MTIME=0

if [ -f "$ED_DATA_FILE" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$ED_DATA_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Extract basic sheet names via python to quickly catch 'do nothing' errors
SHEET_NAMES=$(python3 -c "
import openpyxl, json
try:
    wb = openpyxl.load_workbook('$ED_DATA_FILE', read_only=True)
    print(json.dumps(wb.sheetnames))
except:
    print('[]')
" 2>/dev/null || echo "[]")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "mtime": $MTIME,
    "sheets": $SHEET_NAMES,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="