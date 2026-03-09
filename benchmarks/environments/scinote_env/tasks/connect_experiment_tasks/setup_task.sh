#!/bin/bash
echo "=== Setting up connect_experiment_tasks task ==="

# Clean up previous task files
rm -f /tmp/connect_tasks_result.json 2>/dev/null || true
rm -f /tmp/initial_connection_count 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create prerequisite: project -> experiment -> 3 disconnected tasks
echo "=== Creating prerequisite project, experiment, and tasks ==="

# Create project
PROJ_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM projects WHERE name='Genomics Study';" | tr -d '[:space:]')
if [ "${PROJ_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('Genomics Study', 1, 1, 1, NOW(), NOW(), false, false, false);"
    echo "Created project 'Genomics Study'"
fi
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='Genomics Study' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# Create experiment
EXP_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM experiments WHERE name='DNA Sequencing Pipeline' AND project_id=${PROJECT_ID};" | tr -d '[:space:]')
if [ "${EXP_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('DNA Sequencing Pipeline', ${PROJECT_ID}, 1, 1, false, false, NOW(), NOW(), gen_random_uuid());"
    echo "Created experiment 'DNA Sequencing Pipeline'"
fi
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='DNA Sequencing Pipeline' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"

# Create 3 disconnected tasks with spread-out positions on the canvas
for task_info in "Sample Collection|0|200" "DNA Extraction|300|200" "PCR Amplification|600|200"; do
    TASK_NAME=$(echo "$task_info" | cut -d'|' -f1)
    TASK_X=$(echo "$task_info" | cut -d'|' -f2)
    TASK_Y=$(echo "$task_info" | cut -d'|' -f3)

    T_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE name='${TASK_NAME}' AND experiment_id=${EXPERIMENT_ID};" | tr -d '[:space:]')
    if [ "${T_EXISTS:-0}" = "0" ]; then
        scinote_db_query "INSERT INTO my_modules (name, x, y, experiment_id, created_at, updated_at, archived, workflow_order, created_by_id) VALUES ('${TASK_NAME}', ${TASK_X}, ${TASK_Y}, ${EXPERIMENT_ID}, NOW(), NOW(), false, 0, 1);"
        TASK_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='${TASK_NAME}' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')
        scinote_db_query "INSERT INTO protocols (my_module_id, team_id, protocol_type, created_at, updated_at, archived) VALUES (${TASK_ID}, 1, 0, NOW(), NOW(), false);"
        ensure_user_assignment "MyModule" "$TASK_ID"
        echo "Created task '${TASK_NAME}' at (${TASK_X}, ${TASK_Y})"
    fi
done

# Record initial connection count for this experiment
INITIAL_CONN_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM connections c JOIN my_modules mm ON (c.input_id = mm.id OR c.output_id = mm.id) WHERE mm.experiment_id=${EXPERIMENT_ID};" | tr -d '[:space:]')
echo "${INITIAL_CONN_COUNT:-0}" > /tmp/initial_connection_count
echo "Initial connection count: ${INITIAL_CONN_COUNT:-0}"

# Save experiment ID for export
echo "${EXPERIMENT_ID}" > /tmp/experiment_id

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Connect 'Sample Collection' -> 'DNA Extraction' -> 'PCR Amplification'"
