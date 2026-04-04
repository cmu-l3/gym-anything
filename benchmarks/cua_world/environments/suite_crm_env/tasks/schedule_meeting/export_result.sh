#!/bin/bash
echo "=== Exporting schedule_meeting results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/schedule_meeting_final.png

INITIAL_MEETING_COUNT=$(cat /tmp/initial_meeting_count.txt 2>/dev/null || echo "0")
CURRENT_MEETING_COUNT=$(get_meeting_count)

MEETING_DATA=$(suitecrm_db_query "SELECT id, name, status, date_start, duration_hours, duration_minutes, location, description FROM meetings WHERE name='Adobe Creative Cloud Integration - Technical Architecture Review' AND deleted=0 LIMIT 1")

MEETING_FOUND="false"
if [ -n "$MEETING_DATA" ]; then
    MEETING_FOUND="true"
    M_ID=$(echo "$MEETING_DATA" | awk -F'\t' '{print $1}')
    M_NAME=$(echo "$MEETING_DATA" | awk -F'\t' '{print $2}')
    M_STATUS=$(echo "$MEETING_DATA" | awk -F'\t' '{print $3}')
    M_DATE=$(echo "$MEETING_DATA" | awk -F'\t' '{print $4}')
    M_DUR_H=$(echo "$MEETING_DATA" | awk -F'\t' '{print $5}')
    M_DUR_M=$(echo "$MEETING_DATA" | awk -F'\t' '{print $6}')
    M_LOC=$(echo "$MEETING_DATA" | awk -F'\t' '{print $7}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "meeting_found": ${MEETING_FOUND},
  "meeting_id": "$(json_escape "${M_ID:-}")",
  "name": "$(json_escape "${M_NAME:-}")",
  "status": "$(json_escape "${M_STATUS:-}")",
  "date_start": "$(json_escape "${M_DATE:-}")",
  "duration_hours": "$(json_escape "${M_DUR_H:-}")",
  "duration_minutes": "$(json_escape "${M_DUR_M:-}")",
  "location": "$(json_escape "${M_LOC:-}")",
  "initial_count": ${INITIAL_MEETING_COUNT},
  "current_count": ${CURRENT_MEETING_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/schedule_meeting_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/schedule_meeting_result.json"
echo "$RESULT_JSON"
echo "=== schedule_meeting export complete ==="
