#!/bin/bash
set -u

echo "=== Exporting Optimize Scheduler Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot captured."

# 2. Query Database for Task Status
# We need: repeat_interval, name, uuid, date_changed
TASK_NAME="HL7 Inbound Queue Processor"

QUERY_SQL="
USE openmrs;
SELECT 
    name, 
    repeat_interval, 
    uuid, 
    UNIX_TIMESTAMP(date_changed) as changed_ts,
    UNIX_TIMESTAMP(date_created) as created_ts
FROM scheduler_task_config 
WHERE name = '${TASK_NAME}';
"

# Run query and capture output (tab separated)
DB_RESULT=$(docker exec -i bahmni-openmrsdb mysql -N -u openmrs-user -ppassword < <(echo "$QUERY_SQL") 2>/dev/null)

# Parse Result
# MySQL -N output: name \t repeat_interval \t uuid \t changed_ts \t created_ts
# Note: changed_ts might be NULL if never changed, created_ts shouldn't be.

if [ -z "$DB_RESULT" ]; then
    TASK_FOUND="false"
    FINAL_INTERVAL="null"
    TASK_UUID="null"
    CHANGED_TS="0"
    CREATED_TS="0"
else
    TASK_FOUND="true"
    # Read into variables
    read -r R_NAME R_INTERVAL R_UUID R_CHANGED R_CREATED <<< "$DB_RESULT"
    
    FINAL_INTERVAL="$R_INTERVAL"
    TASK_UUID="$R_UUID"
    CHANGED_TS="${R_CHANGED:-0}" # Default to 0 if NULL/Empty
    CREATED_TS="${R_CREATED:-0}"
fi

# 3. Get Task Start Time
TASK_START_TS=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 4. Check Browser/App State
APP_RUNNING="false"
if pgrep -f "epiphany" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Construct JSON Result
JSON_OUTPUT="/tmp/task_result.json"

cat > "$JSON_OUTPUT" <<EOF
{
    "task_found": ${TASK_FOUND},
    "task_name": "${TASK_NAME}",
    "final_interval": ${FINAL_INTERVAL},
    "task_uuid": "${TASK_UUID}",
    "last_changed_ts": ${CHANGED_TS},
    "created_ts": ${CREATED_TS},
    "task_start_ts": ${TASK_START_TS},
    "app_running": ${APP_RUNNING},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$JSON_OUTPUT"

echo "Exported Data:"
cat "$JSON_OUTPUT"

echo "=== Export Complete ==="