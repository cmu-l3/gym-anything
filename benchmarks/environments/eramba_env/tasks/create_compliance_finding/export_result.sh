#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting results: create_compliance_finding ==="

# 1. Capture final screenshot immediately
take_screenshot /tmp/task_final_state.png

# 2. Load context
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FINDINGS_TABLE=$(cat /tmp/findings_table_name.txt 2>/dev/null || echo "compliance_findings")
INITIAL_COUNT=$(cat /tmp/initial_findings_count.txt 2>/dev/null || echo "0")

# 3. Check for specific finding record
# We look for the specific title requested
TARGET_TITLE="Missing Cryptographic Key Management Procedure"

# Helper to run SQL returning JSON object
# We select relevant fields from the most recently created matching record
RECORD_JSON=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "
SELECT JSON_OBJECT(
    'id', id,
    'title', title,
    'description', description,
    'deadline', COALESCE(deadline, expiration, review, 'NULL'),
    'created_unix', UNIX_TIMESTAMP(created)
)
FROM ${FINDINGS_TABLE}
WHERE title LIKE '%Cryptographic Key Management%'
AND deleted=0
ORDER BY created DESC LIMIT 1;" 2>/dev/null || echo "{}")

if [ -z "$RECORD_JSON" ]; then
    RECORD_JSON="{}"
fi

# 4. Get current total count
CURRENT_COUNT=$(eramba_db_query "SELECT COUNT(*) FROM ${FINDINGS_TABLE} WHERE deleted=0;" 2>/dev/null || echo "0")

# 5. Check if app was running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Gather screenshots for VLM trajectory
# We'll list up to 5 most recent screenshots from the trajectory folder if it exists, plus final
SCREENSHOT_LIST="[]"
if [ -d "/tmp/trajectory_screenshots" ]; then
    SCREENSHOT_LIST=$(ls -t /tmp/trajectory_screenshots/*.png 2>/dev/null | head -5 | jq -R -s -c 'split("\n")[:-1]')
fi

# 7. Construct Result JSON
JSON_OUTPUT=$(jq -n \
    --argjson record "$RECORD_JSON" \
    --arg initial_count "$INITIAL_COUNT" \
    --arg current_count "$CURRENT_COUNT" \
    --arg task_start "$TASK_START" \
    --arg app_running "$APP_RUNNING" \
    --arg final_screenshot "/tmp/task_final_state.png" \
    --argjson trajectory "$SCREENSHOT_LIST" \
    '{
        found_record: $record,
        stats: {
            initial_count: $initial_count,
            current_count: $current_count
        },
        meta: {
            task_start_time: $task_start,
            app_was_running: $app_running,
            final_screenshot_path: $final_screenshot,
            trajectory_screenshots: $trajectory
        }
    }')

# 8. Save to file with permissions
echo "$JSON_OUTPUT" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"