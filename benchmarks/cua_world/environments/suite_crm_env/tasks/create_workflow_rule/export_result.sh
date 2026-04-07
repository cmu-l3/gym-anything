#!/bin/bash
echo "=== Exporting create_workflow_rule results ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query for the created workflow
WF_ID=$(suitecrm_db_query "SELECT id FROM aow_workflow WHERE name LIKE '%Auto-Qualify High-Value Prospects%' AND deleted=0 LIMIT 1" | tr -d '[:space:]')

WF_FOUND="false"
FLOW_MODULE=""
STATUS=""
RUN_WHEN=""
DATE_ENTERED="0"
COND_COUNT="0"
COND_AMOUNT_VAL=""
COND_STAGE_VAL=""
ACTION_COUNT="0"
ACTION_TYPE=""

if [ -n "$WF_ID" ]; then
    WF_FOUND="true"
    FLOW_MODULE=$(suitecrm_db_query "SELECT flow_module FROM aow_workflow WHERE id='$WF_ID'" | tr -d '[:space:]')
    STATUS=$(suitecrm_db_query "SELECT status FROM aow_workflow WHERE id='$WF_ID'" | tr -d '[:space:]')
    RUN_WHEN=$(suitecrm_db_query "SELECT run_when FROM aow_workflow WHERE id='$WF_ID'" | tr -d '[:space:]')
    DATE_ENTERED=$(suitecrm_db_query "SELECT UNIX_TIMESTAMP(date_entered) FROM aow_workflow WHERE id='$WF_ID'" | tr -d '[:space:]')
    
    # Conditions
    COND_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aow_conditions WHERE aow_workflow_id='$WF_ID' AND deleted=0" | tr -d '[:space:]')
    COND_AMOUNT_VAL=$(suitecrm_db_query "SELECT value FROM aow_conditions WHERE aow_workflow_id='$WF_ID' AND field='amount' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
    COND_STAGE_VAL=$(suitecrm_db_query "SELECT value FROM aow_conditions WHERE aow_workflow_id='$WF_ID' AND field='sales_stage' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
    
    # Actions
    ACTION_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aow_actions WHERE aow_workflow_id='$WF_ID' AND deleted=0" | tr -d '[:space:]')
    ACTION_TYPE=$(suitecrm_db_query "SELECT action FROM aow_actions WHERE aow_workflow_id='$WF_ID' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
fi

# Determine if created during task
CREATED_DURING_TASK="false"
if [ "$DATE_ENTERED" -ge "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Build JSON output
RESULT_JSON=$(cat << JSONEOF
{
  "workflow_found": ${WF_FOUND},
  "created_during_task": ${CREATED_DURING_TASK},
  "task_start_time": ${TASK_START},
  "date_entered": ${DATE_ENTERED},
  "flow_module": "$(json_escape "${FLOW_MODULE:-}")",
  "status": "$(json_escape "${STATUS:-}")",
  "run_when": "$(json_escape "${RUN_WHEN:-}")",
  "condition_count": ${COND_COUNT:-0},
  "amount_condition_value": "$(json_escape "${COND_AMOUNT_VAL:-}")",
  "stage_condition_value": "$(json_escape "${COND_STAGE_VAL:-}")",
  "action_count": ${ACTION_COUNT:-0},
  "action_type": "$(json_escape "${ACTION_TYPE:-}")"
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="