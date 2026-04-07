#!/bin/bash
echo "=== Exporting export_routine_pdf task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check for PDF in the Downloads directory
PDF_PATH=$(ls -t /home/ga/Downloads/*.pdf 2>/dev/null | head -1)
PDF_EXISTS="false"
PDF_MTIME=0
PDF_SIZE=0

if [ -n "$PDF_PATH" ] && [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_MTIME=$(stat -c %Y "$PDF_PATH" 2>/dev/null || echo "0")
    PDF_SIZE=$(stat -c %s "$PDF_PATH" 2>/dev/null || echo "0")
    echo "Found PDF at: $PDF_PATH (Size: $PDF_SIZE bytes)"
else
    echo "No PDF found in /home/ga/Downloads/"
fi

# 2. Check Database State
OLD_ROUTINE_COUNT=$(db_query "SELECT COUNT(*) FROM manager_routine WHERE name='Push-Pull-Legs';" | tr -d '[:space:]')
NEW_ROUTINE_COUNT=$(db_query "SELECT COUNT(*) FROM manager_routine WHERE name='Push-Pull-Legs (Hypertrophy Phase)';" | tr -d '[:space:]')

echo "DB State: Old Name Count = ${OLD_ROUTINE_COUNT:-0}, New Name Count = ${NEW_ROUTINE_COUNT:-0}"

# 3. Take final evidence screenshot
take_screenshot /tmp/task_final.png

# 4. Export JSON metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "pdf_exists": $PDF_EXISTS,
    "pdf_path": "${PDF_PATH:-}",
    "pdf_mtime": $PDF_MTIME,
    "pdf_size_bytes": $PDF_SIZE,
    "old_routine_count": ${OLD_ROUTINE_COUNT:-0},
    "new_routine_count": ${NEW_ROUTINE_COUNT:-0}
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="