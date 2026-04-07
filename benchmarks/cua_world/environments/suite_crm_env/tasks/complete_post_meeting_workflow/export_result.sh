#!/bin/bash
echo "=== Exporting complete_post_meeting_workflow results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Meeting Status
echo "Querying meeting status..."
MEET_STATUS=$(suitecrm_db_query "SELECT status FROM meetings WHERE id='meeting-q3-sync-0001' AND deleted=0" | tr -d '\n' | tr -d '\r')

# 3. Query Note (Meeting Minutes)
echo "Querying notes..."
NOTE_DATA=$(suitecrm_db_query "SELECT id, parent_type, parent_id, description FROM notes WHERE name='Q3 Roadmap Sync - Minutes' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

NOTE_FOUND="false"
if [ -n "$NOTE_DATA" ]; then
    NOTE_FOUND="true"
    N_ID=$(echo "$NOTE_DATA" | awk -F'\t' '{print $1}')
    N_PTYPE=$(echo "$NOTE_DATA" | awk -F'\t' '{print $2}')
    N_PID=$(echo "$NOTE_DATA" | awk -F'\t' '{print $3}')
    N_DESC=$(echo "$NOTE_DATA" | awk -F'\t' '{print $4}')
fi

# 4. Query Task (Follow-up Action)
echo "Querying tasks..."
TASK_DATA=$(suitecrm_db_query "SELECT id, parent_type, parent_id, status, priority FROM tasks WHERE name='Draft Q3 SLA Addendum' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

TASK_FOUND="false"
if [ -n "$TASK_DATA" ]; then
    TASK_FOUND="true"
    T_ID=$(echo "$TASK_DATA" | awk -F'\t' '{print $1}')
    T_PTYPE=$(echo "$TASK_DATA" | awk -F'\t' '{print $2}')
    T_PID=$(echo "$TASK_DATA" | awk -F'\t' '{print $3}')
    T_STATUS=$(echo "$TASK_DATA" | awk -F'\t' '{print $4}')
    T_PRIORITY=$(echo "$TASK_DATA" | awk -F'\t' '{print $5}')
fi

# 5. Compile Results into JSON
RESULT_JSON=$(cat << JSONEOF
{
  "meeting_status": "$(json_escape "${MEET_STATUS:-}")",
  "note_found": ${NOTE_FOUND},
  "note_parent_type": "$(json_escape "${N_PTYPE:-}")",
  "note_parent_id": "$(json_escape "${N_PID:-}")",
  "note_description": "$(json_escape "${N_DESC:-}")",
  "task_found": ${TASK_FOUND},
  "task_parent_type": "$(json_escape "${T_PTYPE:-}")",
  "task_parent_id": "$(json_escape "${T_PID:-}")",
  "task_status": "$(json_escape "${T_STATUS:-}")",
  "task_priority": "$(json_escape "${T_PRIORITY:-}")"
}
JSONEOF
)

# 6. Save JSON Safely
safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="