#!/bin/bash
echo "=== Setting up add_task_to_experiment task ==="

# Clean up previous task files
rm -f /tmp/add_task_result.json 2>/dev/null || true
rm -f /tmp/initial_my_module_count 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create prerequisite project and experiment via SQL
echo "=== Creating prerequisite project and experiment ==="

# Create project if not exists
PROJ_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM projects WHERE name='Drug Discovery Pipeline';" | tr -d '[:space:]')
if [ "${PROJ_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('Drug Discovery Pipeline', 1, 1, 1, NOW(), NOW(), false, false, false);"
    echo "Created project 'Drug Discovery Pipeline'"
fi

# Get the project ID
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='Drug Discovery Pipeline' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# Create experiment if not exists
EXP_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM experiments WHERE name='LC-MS Compound Screening' AND project_id=${PROJECT_ID};" | tr -d '[:space:]')
if [ "${EXP_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('LC-MS Compound Screening', ${PROJECT_ID}, 1, 1, false, false, NOW(), NOW(), gen_random_uuid());"
    echo "Created experiment 'LC-MS Compound Screening'"
fi
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='LC-MS Compound Screening' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"

# Record initial task (my_module) count
INITIAL_COUNT=$(get_my_module_count)
echo "${INITIAL_COUNT:-0}" > /tmp/initial_my_module_count
echo "Initial task (my_module) count: ${INITIAL_COUNT:-0}"

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Add task 'Run Mass Spec Calibration' to experiment 'LC-MS Compound Screening'"
