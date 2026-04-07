#!/bin/bash
echo "=== Exporting record_lab_result task results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Generate post-task database snapshot
echo "Generating post-task database snapshot..."
mysqldump -u freemed -pfreemed freemed --skip-extended-insert --compact --no-create-info > /tmp/freemed_final.sql 2>/dev/null

# Perform diff to isolate ONLY newly inserted or modified rows
# Grep "^>" extracts lines that exist in the final DB but NOT in the initial DB
echo "Calculating database diff..."
diff /tmp/freemed_initial.sql /tmp/freemed_final.sql | grep "^>" > /tmp/freemed_diff.txt || true

# Determine if the diff contains any new rows
DIFF_SIZE=$(stat -c %s /tmp/freemed_diff.txt 2>/dev/null || echo "0")
NEW_ROWS_ADDED="false"
if [ "$DIFF_SIZE" -gt 0 ]; then
    NEW_ROWS_ADDED="true"
fi

# Create export JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "task_end_time": $(date +%s),
    "new_rows_added": $NEW_ROWS_ADDED,
    "diff_file_size": $DIFF_SIZE,
    "browser_running": $(pgrep -f firefox > /dev/null && echo "true" || echo "false")
}
EOF

# Safe move and permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json /tmp/freemed_diff.txt 2>/dev/null || sudo chmod 666 /tmp/task_result.json /tmp/freemed_diff.txt 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "Diff file saved to /tmp/freemed_diff.txt ($DIFF_SIZE bytes)"
echo "=== Export complete ==="