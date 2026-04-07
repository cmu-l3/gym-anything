#!/bin/bash
echo "=== Exporting update_task_statuses result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJ_NAME="Pd-Catalyzed Cross-Coupling Study"
EXP_NAME="Suzuki Coupling Optimization Run 5"

# Query the specific tasks for this experiment
# PostgreSQL EXTRACT(EPOCH) gives seconds since 1970
QUERY="SELECT mm.name, mm.state, EXTRACT(EPOCH FROM mm.updated_at)
FROM my_modules mm
JOIN experiments e ON mm.experiment_id = e.id
JOIN projects p ON e.project_id = p.id
WHERE p.name = '${PROJ_NAME}' AND e.name = '${EXP_NAME}';"

TASKS_DATA=$(scinote_db_query "$QUERY")

TASKS_JSON="["
FIRST=true
while IFS='|' read -r name state updated_at; do
    [ -z "$name" ] && continue
    name_clean=$(echo "$name" | sed 's/"/\\"/g' | xargs)
    # Handle potentially empty state or timestamp
    state=${state:-0}
    updated_at=${updated_at:-0}
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        TASKS_JSON="${TASKS_JSON},"
    fi
    TASKS_JSON="${TASKS_JSON}{\"name\": \"${name_clean}\", \"state\": ${state}, \"updated_at\": ${updated_at}}"
done <<< "$TASKS_DATA"
TASKS_JSON="${TASKS_JSON}]"

RESULT_JSON=$(cat << EOF
{
    "task_start_time": ${START_TIME},
    "experiment_tasks": ${TASKS_JSON},
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/update_task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/update_task_result.json"
cat /tmp/update_task_result.json
echo "=== Export complete ==="