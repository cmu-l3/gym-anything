#!/bin/bash
echo "=== Exporting schedule_calendar_event results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/schedule_event_final.png

INITIAL_EVENT_COUNT=$(cat /tmp/initial_event_count.txt 2>/dev/null || echo "0")
CURRENT_EVENT_COUNT=$(get_event_count)

EVENT_DATA=$(vtiger_db_query "SELECT a.activityid, a.subject, a.activitytype, a.date_start, a.time_start, a.due_date, a.time_end, a.status, a.location FROM vtiger_activity a WHERE a.subject='GreenLeaf IoT Pilot Kickoff Meeting' LIMIT 1")

EVENT_FOUND="false"
if [ -n "$EVENT_DATA" ]; then
    EVENT_FOUND="true"
    E_ID=$(echo "$EVENT_DATA" | awk -F'\t' '{print $1}')
    E_SUBJECT=$(echo "$EVENT_DATA" | awk -F'\t' '{print $2}')
    E_TYPE=$(echo "$EVENT_DATA" | awk -F'\t' '{print $3}')
    E_DATE=$(echo "$EVENT_DATA" | awk -F'\t' '{print $4}')
    E_TIME=$(echo "$EVENT_DATA" | awk -F'\t' '{print $5}')
    E_DUE=$(echo "$EVENT_DATA" | awk -F'\t' '{print $6}')
    E_ENDTIME=$(echo "$EVENT_DATA" | awk -F'\t' '{print $7}')
    E_STATUS=$(echo "$EVENT_DATA" | awk -F'\t' '{print $8}')
    E_LOCATION=$(echo "$EVENT_DATA" | awk -F'\t' '{print $9}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "event_found": ${EVENT_FOUND},
  "event_id": "$(json_escape "${E_ID:-}")",
  "subject": "$(json_escape "${E_SUBJECT:-}")",
  "activity_type": "$(json_escape "${E_TYPE:-}")",
  "date_start": "$(json_escape "${E_DATE:-}")",
  "time_start": "$(json_escape "${E_TIME:-}")",
  "due_date": "$(json_escape "${E_DUE:-}")",
  "time_end": "$(json_escape "${E_ENDTIME:-}")",
  "status": "$(json_escape "${E_STATUS:-}")",
  "location": "$(json_escape "${E_LOCATION:-}")",
  "initial_count": ${INITIAL_EVENT_COUNT},
  "current_count": ${CURRENT_EVENT_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/schedule_event_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/schedule_event_result.json"
echo "$RESULT_JSON"
echo "=== schedule_calendar_event export complete ==="
