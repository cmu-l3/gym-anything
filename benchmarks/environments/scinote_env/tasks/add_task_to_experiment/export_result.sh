#!/bin/bash
echo "=== Exporting add_task_to_experiment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/initial_my_module_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_my_module_count)

# Search for the expected task (my_module)
EXPECTED_NAME="Run Mass Spec Calibration"
TASK_DATA=$(scinote_db_query "SELECT mm.id, mm.name, e.name, p.name, mm.created_at FROM my_modules mm JOIN experiments e ON mm.experiment_id = e.id JOIN projects p ON e.project_id = p.id WHERE LOWER(TRIM(mm.name)) = LOWER(TRIM('${EXPECTED_NAME}')) ORDER BY mm.created_at DESC LIMIT 1;")

TASK_FOUND="false"
TASK_ID=""
TASK_NAME=""
EXPERIMENT_NAME=""
PROJECT_NAME=""
TASK_CREATED=""

if [ -n "$TASK_DATA" ]; then
    TASK_FOUND="true"
    TASK_ID=$(echo "$TASK_DATA" | cut -d'|' -f1)
    TASK_NAME=$(echo "$TASK_DATA" | cut -d'|' -f2)
    EXPERIMENT_NAME=$(echo "$TASK_DATA" | cut -d'|' -f3)
    PROJECT_NAME=$(echo "$TASK_DATA" | cut -d'|' -f4)
    TASK_CREATED=$(echo "$TASK_DATA" | cut -d'|' -f5)
fi

# Partial match fallback
PARTIAL_MATCH=""
if [ "$TASK_FOUND" = "false" ]; then
    PARTIAL_MATCH=$(scinote_db_query "SELECT mm.id, mm.name, e.name FROM my_modules mm JOIN experiments e ON mm.experiment_id = e.id WHERE LOWER(mm.name) LIKE '%mass spec%' OR LOWER(mm.name) LIKE '%calibration%' ORDER BY mm.created_at DESC LIMIT 1;")
fi

# Newest task fallback
NEW_TASK=""
if [ "$TASK_FOUND" = "false" ]; then
    NEW_TASK=$(scinote_db_query "SELECT mm.id, mm.name, e.name FROM my_modules mm JOIN experiments e ON mm.experiment_id = e.id ORDER BY mm.created_at DESC LIMIT 1;")
fi

TASK_NAME_ESCAPED=$(json_escape "$TASK_NAME")
EXPERIMENT_NAME_ESCAPED=$(json_escape "$EXPERIMENT_NAME")
PROJECT_NAME_ESCAPED=$(json_escape "$PROJECT_NAME")
PARTIAL_ESCAPED=$(json_escape "$PARTIAL_MATCH")
NEW_TASK_ESCAPED=$(json_escape "$NEW_TASK")

RESULT_JSON=$(cat << EOF
{
    "initial_task_count": ${INITIAL_COUNT:-0},
    "current_task_count": ${CURRENT_COUNT:-0},
    "task_found": ${TASK_FOUND},
    "task": {
        "id": "${TASK_ID}",
        "name": "${TASK_NAME_ESCAPED}",
        "experiment_name": "${EXPERIMENT_NAME_ESCAPED}",
        "project_name": "${PROJECT_NAME_ESCAPED}",
        "created_at": "${TASK_CREATED}"
    },
    "partial_match": "${PARTIAL_ESCAPED}",
    "newest_task": "${NEW_TASK_ESCAPED}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/add_task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/add_task_result.json"
cat /tmp/add_task_result.json
echo "=== Export complete ==="
