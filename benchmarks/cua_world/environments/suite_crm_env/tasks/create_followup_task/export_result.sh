#!/bin/bash
echo "=== Exporting create_followup_task results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Get task counts
INITIAL_TASK_COUNT=$(cat /tmp/initial_task_count.txt 2>/dev/null || echo "0")
CURRENT_TASK_COUNT=$(suitecrm_count "tasks" "deleted=0")

# Query the database for the created task. 
# Replacing newlines in description to ensure AWK parses it safely as a single line.
TASK_DATA=$(suitecrm_db_query "SELECT id, name, status, priority, date_start, date_due, REPLACE(REPLACE(description, '\r', ' '), '\n', ' ') FROM tasks WHERE name='Prepare Proposal for Meridian Retail Group' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

# Fallback: check for partial subject match if exact match fails
if [ -z "$TASK_DATA" ]; then
    TASK_DATA=$(suitecrm_db_query "SELECT id, name, status, priority, date_start, date_due, REPLACE(REPLACE(description, '\r', ' '), '\n', ' ') FROM tasks WHERE name LIKE '%Meridian Retail%' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")
fi

TASK_FOUND="false"
if [ -n "$TASK_DATA" ]; then
    TASK_FOUND="true"
    T_ID=$(echo "$TASK_DATA" | awk -F'\t' '{print $1}')
    T_NAME=$(echo "$TASK_DATA" | awk -F'\t' '{print $2}')
    T_STATUS=$(echo "$TASK_DATA" | awk -F'\t' '{print $3}')
    T_PRIORITY=$(echo "$TASK_DATA" | awk -F'\t' '{print $4}')
    T_START=$(echo "$TASK_DATA" | awk -F'\t' '{print $5}')
    T_DUE=$(echo "$TASK_DATA" | awk -F'\t' '{print $6}')
    T_DESC=$(echo "$TASK_DATA" | awk -F'\t' '{print $7}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "task_found": ${TASK_FOUND},
  "task_id": "$(json_escape "${T_ID:-}")",
  "name": "$(json_escape "${T_NAME:-}")",
  "status": "$(json_escape "${T_STATUS:-}")",
  "priority": "$(json_escape "${T_PRIORITY:-}")",
  "date_start": "$(json_escape "${T_START:-}")",
  "date_due": "$(json_escape "${T_DUE:-}")",
  "description": "$(json_escape "${T_DESC:-}")",
  "initial_count": ${INITIAL_TASK_COUNT},
  "current_count": ${CURRENT_TASK_COUNT},
  "task_start": ${TASK_START},
  "task_end": ${TASK_END}
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== create_followup_task export complete ==="