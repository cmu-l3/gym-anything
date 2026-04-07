#!/bin/bash
echo "=== Exporting create_onboarding_project results ==="

source /workspace/scripts/task_utils.sh

# Record timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# Query database for the newly created project
PROJECT_DATA=$(suitecrm_db_query "SELECT id, name, status, estimated_start_date, estimated_end_date, priority, description FROM project WHERE name='Greenfield Organics Onboarding' AND deleted=0 LIMIT 1")

P_FOUND="false"
TASKS_JSON="[]"

if [ -n "$PROJECT_DATA" ]; then
    P_FOUND="true"
    
    # Extract tab-separated project fields
    P_ID=$(echo "$PROJECT_DATA" | awk -F'\t' '{print $1}')
    P_NAME=$(echo "$PROJECT_DATA" | awk -F'\t' '{print $2}')
    P_STATUS=$(echo "$PROJECT_DATA" | awk -F'\t' '{print $3}')
    P_START=$(echo "$PROJECT_DATA" | awk -F'\t' '{print $4}')
    P_END=$(echo "$PROJECT_DATA" | awk -F'\t' '{print $5}')
    P_PRIORITY=$(echo "$PROJECT_DATA" | awk -F'\t' '{print $6}')
    P_DESC=$(echo "$PROJECT_DATA" | awk -F'\t' '{print $7}')
    
    # Query database for all linked project tasks
    TASKS_DATA=$(suitecrm_db_query "SELECT name, date_start, date_finish, priority, milestone_flag FROM project_task WHERE project_id='${P_ID}' AND deleted=0")
    
    # Format tasks as a JSON array manually
    TASKS_JSON="["
    FIRST_TASK=true
    if [ -n "$TASKS_DATA" ]; then
        while IFS=$'\t' read -r T_NAME T_START T_FINISH T_PRIORITY T_MILESTONE; do
            if [ "$FIRST_TASK" = true ]; then
                FIRST_TASK=false
            else
                TASKS_JSON="${TASKS_JSON},"
            fi
            
            # Remove any stray carriage returns
            T_MILESTONE=$(echo "$T_MILESTONE" | tr -d '\r')
            
            TASKS_JSON="${TASKS_JSON}{\"name\": \"$(json_escape "$T_NAME")\", \"date_start\": \"$(json_escape "$T_START")\", \"date_finish\": \"$(json_escape "$T_FINISH")\", \"priority\": \"$(json_escape "$T_PRIORITY")\", \"milestone_flag\": \"$(json_escape "$T_MILESTONE")\"}"
        done <<< "$TASKS_DATA"
    fi
    TASKS_JSON="${TASKS_JSON}]"
fi

# Build standard JSON output using heredoc
RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "project_found": ${P_FOUND},
  "project": {
    "id": "$(json_escape "${P_ID:-}")",
    "name": "$(json_escape "${P_NAME:-}")",
    "status": "$(json_escape "${P_STATUS:-}")",
    "estimated_start_date": "$(json_escape "${P_START:-}")",
    "estimated_end_date": "$(json_escape "${P_END:-}")",
    "priority": "$(json_escape "${P_PRIORITY:-}")",
    "description": "$(json_escape "${P_DESC:-}")"
  },
  "tasks": ${TASKS_JSON}
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "=== Export complete ==="