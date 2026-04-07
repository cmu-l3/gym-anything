#!/bin/bash
echo "=== Exporting post_demo_sales_workflow results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query Opportunity State
POT_DATA=$(vtiger_db_query "SELECT p.potentialid, p.sales_stage, p.probability, UNIX_TIMESTAMP(c.modifiedtime) FROM vtiger_potential p JOIN vtiger_crmentity c ON p.potentialid=c.crmid WHERE p.potentialname='GlobalTech - Enterprise Software License' LIMIT 1")

POT_FOUND="false"
if [ -n "$POT_DATA" ]; then
    POT_FOUND="true"
    P_ID=$(echo "$POT_DATA" | awk -F'\t' '{print $1}')
    P_STAGE=$(echo "$POT_DATA" | awk -F'\t' '{print $2}')
    P_PROB=$(echo "$POT_DATA" | awk -F'\t' '{print $3}')
    P_MODIFIED=$(echo "$POT_DATA" | awk -F'\t' '{print $4}')
else
    P_ID="0"
fi

# 4. Query Linked Meeting Activity
MEETING_DATA=$(vtiger_db_query "SELECT a.activityid, a.activitytype, a.eventstatus, UNIX_TIMESTAMP(c.createdtime) FROM vtiger_activity a JOIN vtiger_crmentity c ON a.activityid=c.crmid JOIN vtiger_seactivityrel rel ON a.activityid=rel.activityid WHERE a.subject='Product Demo and Q&A' AND rel.crmid=$P_ID LIMIT 1")

MEETING_FOUND="false"
if [ -n "$MEETING_DATA" ]; then
    MEETING_FOUND="true"
    M_ID=$(echo "$MEETING_DATA" | awk -F'\t' '{print $1}')
    M_TYPE=$(echo "$MEETING_DATA" | awk -F'\t' '{print $2}')
    M_STATUS=$(echo "$MEETING_DATA" | awk -F'\t' '{print $3}')
    M_CREATED=$(echo "$MEETING_DATA" | awk -F'\t' '{print $4}')
fi

# 5. Query Linked Task Activity
TASK_DATA=$(vtiger_db_query "SELECT a.activityid, a.activitytype, a.status, a.priority, UNIX_TIMESTAMP(c.createdtime) FROM vtiger_activity a JOIN vtiger_crmentity c ON a.activityid=c.crmid JOIN vtiger_seactivityrel rel ON a.activityid=rel.activityid WHERE a.subject='Draft and Send Enterprise Proposal' AND rel.crmid=$P_ID LIMIT 1")

TASK_FOUND="false"
if [ -n "$TASK_DATA" ]; then
    TASK_FOUND="true"
    T_ID=$(echo "$TASK_DATA" | awk -F'\t' '{print $1}')
    T_TYPE=$(echo "$TASK_DATA" | awk -F'\t' '{print $2}')
    T_STATUS=$(echo "$TASK_DATA" | awk -F'\t' '{print $3}')
    T_PRIORITY=$(echo "$TASK_DATA" | awk -F'\t' '{print $4}')
    T_CREATED=$(echo "$TASK_DATA" | awk -F'\t' '{print $5}')
fi

# 6. Format JSON Output
RESULT_JSON=$(cat << JSONEOF
{
  "task_start": ${TASK_START},
  "task_end": ${TASK_END},
  "opportunity": {
    "found": ${POT_FOUND},
    "id": "$(json_escape "${P_ID:-}")",
    "sales_stage": "$(json_escape "${P_STAGE:-}")",
    "probability": "$(json_escape "${P_PROB:-}")",
    "modified_time": "$(json_escape "${P_MODIFIED:-}")"
  },
  "meeting": {
    "found": ${MEETING_FOUND},
    "id": "$(json_escape "${M_ID:-}")",
    "type": "$(json_escape "${M_TYPE:-}")",
    "status": "$(json_escape "${M_STATUS:-}")",
    "created_time": "$(json_escape "${M_CREATED:-}")"
  },
  "task": {
    "found": ${TASK_FOUND},
    "id": "$(json_escape "${T_ID:-}")",
    "type": "$(json_escape "${T_TYPE:-}")",
    "status": "$(json_escape "${T_STATUS:-}")",
    "priority": "$(json_escape "${T_PRIORITY:-}")",
    "created_time": "$(json_escape "${T_CREATED:-}")"
  }
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== post_demo_sales_workflow export complete ==="