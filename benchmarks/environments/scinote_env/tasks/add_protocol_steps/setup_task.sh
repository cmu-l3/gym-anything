#!/bin/bash
echo "=== Setting up add_protocol_steps task ==="

# Clean up previous task files
rm -f /tmp/add_protocol_steps_result.json 2>/dev/null || true
rm -f /tmp/initial_step_count 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create prerequisite: project -> experiment -> task (my_module) with an empty protocol
echo "=== Creating prerequisite project, experiment, and task ==="

# Create project
PROJ_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM projects WHERE name='Protein Research Initiative';" | tr -d '[:space:]')
if [ "${PROJ_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('Protein Research Initiative', 1, 1, 1, NOW(), NOW(), false, false, false);"
    echo "Created project 'Protein Research Initiative'"
fi
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='Protein Research Initiative' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# Create experiment
EXP_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM experiments WHERE name='Biochemistry Lab Work' AND project_id=${PROJECT_ID};" | tr -d '[:space:]')
if [ "${EXP_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('Biochemistry Lab Work', ${PROJECT_ID}, 1, 1, false, false, NOW(), NOW(), gen_random_uuid());"
    echo "Created experiment 'Biochemistry Lab Work'"
fi
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='Biochemistry Lab Work' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"

# Create task (my_module) with an empty protocol
TASK_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE name='Enzyme Kinetics Assay' AND experiment_id=${EXPERIMENT_ID};" | tr -d '[:space:]')
if [ "${TASK_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO my_modules (name, x, y, experiment_id, created_at, updated_at, archived, workflow_order, created_by_id) VALUES ('Enzyme Kinetics Assay', 0, 0, ${EXPERIMENT_ID}, NOW(), NOW(), false, 0, 1);"
    echo "Created task 'Enzyme Kinetics Assay'"
fi
TASK_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='Enzyme Kinetics Assay' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "MyModule" "$TASK_ID"

# Create an empty protocol for the task (type 0 = unlinked)
PROTO_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM protocols WHERE my_module_id=${TASK_ID};" | tr -d '[:space:]')
if [ "${PROTO_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO protocols (name, my_module_id, team_id, protocol_type, created_at, updated_at, archived) VALUES ('Enzyme Kinetics Protocol', ${TASK_ID}, 1, 0, NOW(), NOW(), false);"
    echo "Created empty protocol for task"
fi

# Record initial step count for this task's protocol
PROTOCOL_ID=$(scinote_db_query "SELECT id FROM protocols WHERE my_module_id=${TASK_ID} LIMIT 1;" | tr -d '[:space:]')
INITIAL_STEP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM steps WHERE protocol_id=${PROTOCOL_ID};" | tr -d '[:space:]')
echo "${INITIAL_STEP_COUNT:-0}" > /tmp/initial_step_count
echo "Initial step count: ${INITIAL_STEP_COUNT:-0}"

# Save IDs for export script
echo "${TASK_ID}" > /tmp/task_module_id
echo "${PROTOCOL_ID}" > /tmp/protocol_id

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Add protocol steps to 'Enzyme Kinetics Assay'"
