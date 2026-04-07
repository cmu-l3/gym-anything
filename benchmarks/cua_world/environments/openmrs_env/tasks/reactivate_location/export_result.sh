#!/bin/bash
# Export: reactivate_location task
# Checks the database state of the location

set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Target UUID matching setup script
LOC_UUID="150141AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for final state
# We need: retired status, date_changed (to verify it happened during task), and changed_by
# Using mysql/mariadb directly via helper
# location_id is internal, but we query by uuid
SQL="SELECT retired, date_changed, date_retired FROM location WHERE uuid='$LOC_UUID'"
DB_RESULT=$(omrs_db_query "$SQL")

# Parse DB result (tab separated: retired \t date_changed \t date_retired)
# Example output: 0    2023-10-27 10:00:00    NULL
RETIRED=$(echo "$DB_RESULT" | awk '{print $1}')
DATE_CHANGED=$(echo "$DB_RESULT" | awk '{print $2" "$3}') # Combined date+time

# 3. Get Task Start Time
TASK_START_TIMESTAMP=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 4. Check if UI shows the location (sanity check via grep on page source if we could, 
# but simple DB check is robust enough). 

# 5. Convert SQL datetime to timestamp for comparison
# Handle potential NULLs or empty strings
if [ -z "$DATE_CHANGED" ] || [ "$DATE_CHANGED" == "NULL" ]; then
    CHANGED_TIMESTAMP=0
else
    CHANGED_TIMESTAMP=$(date -d "$DATE_CHANGED" +%s 2>/dev/null || echo "0")
fi

echo "DB State - Retired: $RETIRED"
echo "DB State - Date Changed: $DATE_CHANGED ($CHANGED_TIMESTAMP)"
echo "Task Start: $TASK_START_TIMESTAMP"

# 6. Create JSON Output
# Use python to generate valid JSON to avoid quoting issues
python3 -c "
import json
import sys

result = {
    'location_uuid': '$LOC_UUID',
    'retired': $RETIRED,
    'changed_timestamp': $CHANGED_TIMESTAMP,
    'task_start_timestamp': $TASK_START_TIMESTAMP,
    'final_screenshot_path': '/tmp/task_final.png'
}
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="