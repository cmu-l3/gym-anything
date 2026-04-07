#!/bin/bash
set -e

echo "=== Exporting rename_project_entities task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Load entity IDs
PROJECT_ID=$(cat /tmp/task_project_id.txt 2>/dev/null | tr -d '[:space:]')
EXPERIMENT_ID=$(cat /tmp/task_experiment_id.txt 2>/dev/null | tr -d '[:space:]')
MY_MODULE_ID=$(cat /tmp/task_my_module_id.txt 2>/dev/null | tr -d '[:space:]')
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null | tr -d '[:space:]')

# Fetch current names from database
CURRENT_PROJECT_NAME=$(scinote_db_query "SELECT name FROM projects WHERE id=${PROJECT_ID};" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null || echo "")
CURRENT_EXPERIMENT_NAME=$(scinote_db_query "SELECT name FROM experiments WHERE id=${EXPERIMENT_ID};" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null || echo "")
CURRENT_TASK_NAME=$(scinote_db_query "SELECT name FROM my_modules WHERE id=${MY_MODULE_ID};" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null || echo "")

# Fetch current timestamps (epoch) to check for anti-gaming
PROJECT_UPDATED=$(scinote_db_query "SELECT EXTRACT(EPOCH FROM updated_at)::bigint FROM projects WHERE id=${PROJECT_ID};" | tr -d '[:space:]' 2>/dev/null || echo "0")
EXPERIMENT_UPDATED=$(scinote_db_query "SELECT EXTRACT(EPOCH FROM updated_at)::bigint FROM experiments WHERE id=${EXPERIMENT_ID};" | tr -d '[:space:]' 2>/dev/null || echo "0")
TASK_UPDATED=$(scinote_db_query "SELECT EXTRACT(EPOCH FROM updated_at)::bigint FROM my_modules WHERE id=${MY_MODULE_ID};" | tr -d '[:space:]' 2>/dev/null || echo "0")

# Write to JSON properly escaped
RESULT_JSON=$(cat << EOF
{
    "task_start_time": ${TASK_START_TIME:-0},
    "project": {
        "id": "${PROJECT_ID}",
        "name": "$(json_escape "$CURRENT_PROJECT_NAME")",
        "updated_at": ${PROJECT_UPDATED:-0}
    },
    "experiment": {
        "id": "${EXPERIMENT_ID}",
        "name": "$(json_escape "$CURRENT_EXPERIMENT_NAME")",
        "updated_at": ${EXPERIMENT_UPDATED:-0}
    },
    "task": {
        "id": "${MY_MODULE_ID}",
        "name": "$(json_escape "$CURRENT_TASK_NAME")",
        "updated_at": ${TASK_UPDATED:-0}
    },
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF
)

safe_write_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="