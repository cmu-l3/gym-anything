#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Look for the exported CSV file
TARGET_PATH="/home/ga/Documents/closed_won_deals.csv"
EXACT_PATH_USED="false"
DOWNLOADED_AT_ALL="false"
FILE_FOUND="false"
FOUND_FILE_PATH=""

if [ -f "$TARGET_PATH" ]; then
    EXACT_PATH_USED="true"
    DOWNLOADED_AT_ALL="true"
    FILE_FOUND="true"
    FOUND_FILE_PATH="$TARGET_PATH"
    cp "$TARGET_PATH" /tmp/agent_export.csv 2>/dev/null
else
    # Check if they at least downloaded it to Downloads
    LATEST_CSV=$(find /home/ga/Downloads/ -maxdepth 1 -name "*.csv" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    if [ -n "$LATEST_CSV" ] && [ -f "$LATEST_CSV" ]; then
        DOWNLOADED_AT_ALL="true"
        FILE_FOUND="true"
        FOUND_FILE_PATH="$LATEST_CSV"
        cp "$LATEST_CSV" /tmp/agent_export.csv 2>/dev/null
    fi
fi

# 2. Extract Apache logs to verify they actually used the SuiteCRM UI Export
# SuiteCRM export hits index.php?entryPoint=export
docker exec suitecrm-app grep "export" /var/log/apache2/access.log > /tmp/export_logs.txt 2>/dev/null || true
chmod 666 /tmp/export_logs.txt 2>/dev/null || sudo chmod 666 /tmp/export_logs.txt 2>/dev/null || true

# 3. Create JSON Result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "exact_path_used": $EXACT_PATH_USED,
  "downloaded_at_all": $DOWNLOADED_AT_ALL,
  "file_found": $FILE_FOUND,
  "found_file_path": "$(json_escape "$FOUND_FILE_PATH")"
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="