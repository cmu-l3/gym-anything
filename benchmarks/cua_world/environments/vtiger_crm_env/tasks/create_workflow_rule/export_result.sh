#!/bin/bash
echo "=== Exporting create_workflow_rule results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_WF_COUNT=$(cat /tmp/initial_wf_count.txt 2>/dev/null || echo "0")
CURRENT_WF_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM com_vtiger_workflows WHERE module_name='Potentials'" | tr -d '[:space:]')

# Find the latest Potentials workflow to evaluate
WF_DATA=$(vtiger_db_query "SELECT workflow_id, summary, execution_condition, status, test FROM com_vtiger_workflows WHERE module_name='Potentials' ORDER BY workflow_id DESC LIMIT 1")

WF_FOUND="false"
W_ID=""
W_SUMMARY=""
W_EXEC=""
W_STATUS=""
W_TEST=""
T_SUMMARY=""
T_TASK=""

if [ -n "$WF_DATA" ]; then
    WF_FOUND="true"
    # Parse tab-separated values
    W_ID=$(echo "$WF_DATA" | awk -F'\t' '{print $1}')
    W_SUMMARY=$(echo "$WF_DATA" | awk -F'\t' '{print $2}')
    W_EXEC=$(echo "$WF_DATA" | awk -F'\t' '{print $3}')
    W_STATUS=$(echo "$WF_DATA" | awk -F'\t' '{print $4}')
    W_TEST=$(echo "$WF_DATA" | awk -F'\t' '{print $5}')

    # Fetch corresponding task
    TASK_DATA=$(vtiger_db_query "SELECT summary, task FROM com_vtiger_workflowtasks WHERE workflow_id=$W_ID LIMIT 1")
    if [ -n "$TASK_DATA" ]; then
        T_SUMMARY=$(echo "$TASK_DATA" | awk -F'\t' '{print $1}')
        T_TASK=$(echo "$TASK_DATA" | awk -F'\t' '{print $2}')
    fi
fi

# Build JSON using escaping utility from task_utils.sh
RESULT_JSON=$(cat << JSONEOF
{
  "wf_found": ${WF_FOUND},
  "initial_count": ${INITIAL_WF_COUNT:-0},
  "current_count": ${CURRENT_WF_COUNT:-0},
  "task_start_time": ${TASK_START:-0},
  "wf_id": "$(json_escape "${W_ID:-}")",
  "summary": "$(json_escape "${W_SUMMARY:-}")",
  "exec_condition": "$(json_escape "${W_EXEC:-}")",
  "status": "$(json_escape "${W_STATUS:-}")",
  "test": "$(json_escape "${W_TEST:-}")",
  "task_summary": "$(json_escape "${T_SUMMARY:-}")",
  "task_data": "$(json_escape "${T_TASK:-}")"
}
JSONEOF
)

safe_write_result "/tmp/workflow_task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/workflow_task_result.json"
echo "=== create_workflow_rule export complete ==="