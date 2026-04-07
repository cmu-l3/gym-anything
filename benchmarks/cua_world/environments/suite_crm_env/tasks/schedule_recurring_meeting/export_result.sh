#!/bin/bash
echo "=== Exporting schedule_recurring_meeting results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/schedule_recurring_meeting_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

INITIAL_MEETING_COUNT=$(cat /tmp/initial_meeting_count.txt 2>/dev/null || echo "0")
CURRENT_MEETING_COUNT=$(get_meeting_count)

# Query for the created meetings
# A recurring meeting creates multiple entries with the same name.
MEETINGS_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM meetings WHERE name='Pilot Status Sync' AND deleted=0")

# Fetch details of one of them to check parent_type, parent_id, and description
MEETING_DATA=$(suitecrm_db_query "SELECT id, name, description, parent_type, parent_id, date_start, date_entered FROM meetings WHERE name='Pilot Status Sync' AND deleted=0 LIMIT 1")

MEETING_FOUND="false"
M_ID=""
M_NAME=""
M_DESC=""
M_PARENT_TYPE=""
M_PARENT_ID=""
M_DATE_START=""
M_DATE_ENTERED=""

if [ -n "$MEETING_DATA" ]; then
    MEETING_FOUND="true"
    M_ID=$(echo "$MEETING_DATA" | awk -F'\t' '{print $1}')
    M_NAME=$(echo "$MEETING_DATA" | awk -F'\t' '{print $2}')
    M_DESC=$(echo "$MEETING_DATA" | awk -F'\t' '{print $3}')
    M_PARENT_TYPE=$(echo "$MEETING_DATA" | awk -F'\t' '{print $4}')
    M_PARENT_ID=$(echo "$MEETING_DATA" | awk -F'\t' '{print $5}')
    M_DATE_START=$(echo "$MEETING_DATA" | awk -F'\t' '{print $6}')
    M_DATE_ENTERED=$(echo "$MEETING_DATA" | awk -F'\t' '{print $7}')
fi

# Query Account name by ID if parent type is Accounts
M_PARENT_NAME=""
if [ "$M_PARENT_TYPE" = "Accounts" ] && [ -n "$M_PARENT_ID" ]; then
    M_PARENT_NAME=$(suitecrm_db_query "SELECT name FROM accounts WHERE id='$M_PARENT_ID' AND deleted=0")
fi

# Convert date entered to unix timestamp to check if created during task
M_DATE_ENTERED_TS="0"
if [ -n "$M_DATE_ENTERED" ]; then
    M_DATE_ENTERED_TS=$(date -d "$M_DATE_ENTERED" +%s 2>/dev/null || echo "0")
fi

CREATED_DURING_TASK="false"
# SuiteCRM might store date_entered in UTC which can cause timezone mismatches with task start timestamp,
# so we also check if the count increased.
if [ "$M_DATE_ENTERED_TS" -ge "$TASK_START" ] || [ "$INITIAL_MEETING_COUNT" -lt "$CURRENT_MEETING_COUNT" ]; then
    CREATED_DURING_TASK="true"
fi

RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "meeting_found": ${MEETING_FOUND},
  "meeting_count": ${MEETINGS_COUNT:-0},
  "meeting_id": "$(json_escape "${M_ID:-}")",
  "name": "$(json_escape "${M_NAME:-}")",
  "description": "$(json_escape "${M_DESC:-}")",
  "parent_type": "$(json_escape "${M_PARENT_TYPE:-}")",
  "parent_name": "$(json_escape "${M_PARENT_NAME:-}")",
  "date_start": "$(json_escape "${M_DATE_START:-}")",
  "created_during_task": ${CREATED_DURING_TASK},
  "initial_count": ${INITIAL_MEETING_COUNT},
  "current_count": ${CURRENT_MEETING_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/schedule_recurring_meeting_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/schedule_recurring_meeting_result.json"
echo "$RESULT_JSON"
echo "=== schedule_recurring_meeting export complete ==="