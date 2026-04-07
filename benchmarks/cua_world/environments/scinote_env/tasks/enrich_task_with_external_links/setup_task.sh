#!/bin/bash
echo "=== Setting up enrich_task_with_external_links task ==="

# Clean up previous task files
rm -f /tmp/enrich_task_result.json 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "=== Creating prerequisite project, experiment, and task ==="

# Create project
PROJ_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM projects WHERE name='CRISPR Assay Development';" | tr -d '[:space:]')
if [ "${PROJ_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('CRISPR Assay Development', 1, 1, 1, NOW(), NOW(), false, false, false);"
    echo "Created project 'CRISPR Assay Development'"
fi
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='CRISPR Assay Development' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# Create experiment
EXP_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM experiments WHERE name='In vitro Cleavage' AND project_id=${PROJECT_ID};" | tr -d '[:space:]')
if [ "${EXP_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('In vitro Cleavage', ${PROJECT_ID}, 1, 1, false, false, NOW(), NOW(), gen_random_uuid());"
    echo "Created experiment 'In vitro Cleavage'"
fi
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='In vitro Cleavage' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"

# Create task (my_module) with an EMPTY description
TASK_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE name='Cas9 RNP Preparation' AND experiment_id=${EXPERIMENT_ID};" | tr -d '[:space:]')
if [ "${TASK_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO my_modules (name, description, x, y, experiment_id, created_at, updated_at, archived, workflow_order, created_by_id) VALUES ('Cas9 RNP Preparation', '', 0, 0, ${EXPERIMENT_ID}, NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day', false, 0, 1);"
    echo "Created task 'Cas9 RNP Preparation'"
else
    # Ensure description is empty and updated_at is in the past
    scinote_db_query "UPDATE my_modules SET description='', updated_at = NOW() - INTERVAL '1 day' WHERE name='Cas9 RNP Preparation' AND experiment_id=${EXPERIMENT_ID};"
    echo "Reset task 'Cas9 RNP Preparation'"
fi
TASK_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='Cas9 RNP Preparation' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "MyModule" "$TASK_ID"

# Record the initial updated_at timestamp (epoch) for the task
INITIAL_UPDATED_AT=$(scinote_db_query "SELECT extract(epoch from updated_at) FROM my_modules WHERE id=${TASK_ID};" | tr -d '[:space:]' | cut -d'.' -f1)
echo "${INITIAL_UPDATED_AT:-0}" > /tmp/initial_task_updated_at

# Save IDs for export script
echo "${TASK_ID}" > /tmp/task_module_id

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="