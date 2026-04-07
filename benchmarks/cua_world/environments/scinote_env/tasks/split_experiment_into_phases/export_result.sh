#!/bin/bash
echo "=== Exporting split_experiment_into_phases result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORIGINAL_EXP_ID=$(cat /tmp/original_experiment_id 2>/dev/null || echo "0")
PROJECT_ID=$(scinote_db_query "SELECT project_id FROM experiments WHERE id=${ORIGINAL_EXP_ID};" | tr -d '[:space:]')

# 1. Original Experiment info
ORIGINAL_EXP_NAME=$(scinote_db_query "SELECT name FROM experiments WHERE id=${ORIGINAL_EXP_ID};" | tr -d '\n' | sed 's/"/\\"/g; s/[[:space:]]*$//')
ORIG_EXP_UPDATED=$(scinote_db_query "SELECT extract(epoch from updated_at) FROM experiments WHERE id=${ORIGINAL_EXP_ID};" | tr -d '[:space:]' | cut -d'.' -f1)

# 2. Find new experiment "Phase 2: Selection" in the same project
NEW_EXP_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='Phase 2: Selection' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')

if [ -n "$NEW_EXP_ID" ]; then
    NEW_EXP_CREATED=$(scinote_db_query "SELECT extract(epoch from created_at) FROM experiments WHERE id=${NEW_EXP_ID};" | tr -d '[:space:]' | cut -d'.' -f1)
else
    NEW_EXP_CREATED=0
fi

# 3. For each task, get its current experiment_id
TASKS=("Media Prep" "Cell Seeding" "Transfection Mix" "Incubation" "Selection" "Expansion")

TASKS_JSON="{"
FIRST=true
for TASK in "${TASKS[@]}"; do
    # Find the task anywhere in the database since names are strictly unique in this setup
    TASK_EXP_ID=$(scinote_db_query "SELECT experiment_id FROM my_modules WHERE name='$TASK' ORDER BY updated_at DESC LIMIT 1;" | tr -d '[:space:]')
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        TASKS_JSON="${TASKS_JSON},"
    fi
    TASKS_JSON="${TASKS_JSON}\"$TASK\": \"${TASK_EXP_ID}\""
done
TASKS_JSON="${TASKS_JSON}}"

RESULT_JSON=$(cat << EOF
{
    "task_start": ${TASK_START:-0},
    "original_experiment_id": "${ORIGINAL_EXP_ID}",
    "original_experiment_current_name": "${ORIGINAL_EXP_NAME}",
    "original_experiment_updated": ${ORIG_EXP_UPDATED:-0},
    "new_experiment_id": "${NEW_EXP_ID}",
    "new_experiment_created": ${NEW_EXP_CREATED:-0},
    "tasks": ${TASKS_JSON},
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/split_experiment_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/split_experiment_result.json"
cat /tmp/split_experiment_result.json
echo "=== Export complete ==="