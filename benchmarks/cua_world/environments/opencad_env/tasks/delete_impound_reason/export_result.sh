#!/bin/bash
echo "=== Exporting delete_impound_reason result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve setup data
COL_NAME=$(cat /tmp/impound_col_name.txt 2>/dev/null || echo "name")
INITIAL_COUNT=$(cat /tmp/initial_impound_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if target still exists
TARGET_EXISTS_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM impound_reasons WHERE \`${COL_NAME}\` = 'Obstructing Machinery'")
if [ "$TARGET_EXISTS_COUNT" -eq "0" ]; then
    TARGET_REMOVED="true"
else
    TARGET_REMOVED="false"
fi

# 2. Get current total count
CURRENT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM impound_reasons")

# 3. Check for other records (sanity check to ensure table wasn't wiped)
OTHER_RECORDS_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM impound_reasons WHERE \`${COL_NAME}\` != 'Obstructing Machinery'")

# 4. Check if admin panel was accessed (simple check on active window title or similar not always reliable, rely on outcome)
# We can check logs if available, but outcome is primary.

# Prepare JSON result
RESULT_JSON=$(cat << EOF
{
    "target_removed": $TARGET_REMOVED,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "other_records_count": ${OTHER_RECORDS_COUNT:-0},
    "column_used": "${COL_NAME}",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/delete_impound_reason_result.json

echo "Result saved to /tmp/delete_impound_reason_result.json"
cat /tmp/delete_impound_reason_result.json
echo "=== Export complete ==="