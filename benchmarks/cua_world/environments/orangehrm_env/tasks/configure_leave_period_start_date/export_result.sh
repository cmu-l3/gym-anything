#!/bin/bash
set -e
echo "=== Exporting configure_leave_period_start_date results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Final Database State
# Retrieve the configured start month and day
# OrangeHRM 5.x might use 'key' or 'name' column depending on exact schema version, try both
FINAL_MONTH=$(orangehrm_db_query "SELECT value FROM hs_hr_config WHERE key='leave_period_start_month' OR name='leave_period_start_month' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
FINAL_DAY=$(orangehrm_db_query "SELECT value FROM hs_hr_config WHERE key='leave_period_start_day' OR name='leave_period_start_day' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

# Handle empty results
FINAL_MONTH=${FINAL_MONTH:-"0"}
FINAL_DAY=${FINAL_DAY:-"0"}

# 3. Get Initial State for comparison
INITIAL_MONTH=$(cat /tmp/initial_month.txt 2>/dev/null || echo "1")
INITIAL_DAY=$(cat /tmp/initial_day.txt 2>/dev/null || echo "1")

# 4. Check Config Change Timestamp (Anti-gaming approximation)
# Since we don't have a direct timestamp on hs_hr_config in all versions, 
# we rely on value change + task execution time window.
CHANGED_DURING_TASK="false"
if [ "$FINAL_MONTH" != "$INITIAL_MONTH" ] || [ "$FINAL_DAY" != "$INITIAL_DAY" ]; then
    CHANGED_DURING_TASK="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_month": "$INITIAL_MONTH",
    "initial_day": "$INITIAL_DAY",
    "final_month": "$FINAL_MONTH",
    "final_day": "$FINAL_DAY",
    "config_changed": $CHANGED_DURING_TASK,
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="