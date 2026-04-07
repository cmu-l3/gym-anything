#!/bin/bash
echo "=== Setting up add_comments_to_task task ==="

# Clean up previous task files
rm -f /tmp/add_comments_result.json 2>/dev/null || true
rm -f /tmp/table_dump_*.txt 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Creating prerequisite project, experiment, and task ==="

# 1. Create Project
PROJ_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM projects WHERE name='HPLC Method Development - Compound ABX-1431';" | tr -d '[:space:]')
if [ "${PROJ_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('HPLC Method Development - Compound ABX-1431', 1, 1, 1, NOW(), NOW(), false, false, false);"
    echo "Created project 'HPLC Method Development - Compound ABX-1431'"
fi
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='HPLC Method Development - Compound ABX-1431' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# 2. Create Experiment
EXP_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM experiments WHERE name='Column Screening Phase 1' AND project_id=${PROJECT_ID};" | tr -d '[:space:]')
if [ "${EXP_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('Column Screening Phase 1', ${PROJECT_ID}, 1, 1, false, false, NOW(), NOW(), gen_random_uuid());"
    echo "Created experiment 'Column Screening Phase 1'"
fi
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='Column Screening Phase 1' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"

# 3. Create Task (my_module)
TASK_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE name='C18 Column - Gradient Test A' AND experiment_id=${EXPERIMENT_ID};" | tr -d '[:space:]')
if [ "${TASK_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO my_modules (name, x, y, experiment_id, created_at, updated_at, archived, workflow_order, created_by_id) VALUES ('C18 Column - Gradient Test A', 0, 0, ${EXPERIMENT_ID}, NOW(), NOW(), false, 0, 1);"
    echo "Created task 'C18 Column - Gradient Test A'"
fi
TASK_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='C18 Column - Gradient Test A' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "MyModule" "$TASK_ID"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="