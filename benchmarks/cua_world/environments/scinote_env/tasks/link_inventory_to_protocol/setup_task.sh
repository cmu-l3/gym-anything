#!/bin/bash
set -e
echo "=== Setting up link_inventory_to_protocol task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous task files
rm -f /tmp/link_inventory_result.json 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Creating prerequisite Data ==="

# 1. Create Repository (Inventory) and Item
scinote_db_query "INSERT INTO repositories (name, team_id, created_at, updated_at) VALUES ('Enzymes', 1, NOW(), NOW());"
REPO_ID=$(scinote_db_query "SELECT id FROM repositories WHERE name='Enzymes' LIMIT 1;" | tr -d '[:space:]')

scinote_db_query "INSERT INTO repository_rows (name, repository_id, created_at, updated_at) VALUES ('Taq Polymerase', ${REPO_ID}, NOW(), NOW());"
ROW_ID=$(scinote_db_query "SELECT id FROM repository_rows WHERE name='Taq Polymerase' AND repository_id=${REPO_ID} LIMIT 1;" | tr -d '[:space:]')
echo "${ROW_ID}" > /tmp/row_id

# 2. Create Project -> Experiment -> Task (MyModule)
scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('Protocol Library', 1, 1, 1, NOW(), NOW(), false, false, false);"
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='Protocol Library' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('Templates', ${PROJECT_ID}, 1, 1, false, false, NOW(), NOW(), gen_random_uuid());"
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='Templates' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"

scinote_db_query "INSERT INTO my_modules (name, x, y, experiment_id, created_at, updated_at, archived, workflow_order, created_by_id) VALUES ('PCR Protocol Template', 0, 0, ${EXPERIMENT_ID}, NOW(), NOW(), false, 0, 1);"
TASK_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='PCR Protocol Template' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "MyModule" "$TASK_ID"

# 3. Create Protocol and Step
scinote_db_query "INSERT INTO protocols (name, my_module_id, team_id, protocol_type, created_at, updated_at, archived) VALUES ('Standard PCR v1', ${TASK_ID}, 1, 0, NOW(), NOW(), false);"
PROTOCOL_ID=$(scinote_db_query "SELECT id FROM protocols WHERE name='Standard PCR v1' AND my_module_id=${TASK_ID} LIMIT 1;" | tr -d '[:space:]')

scinote_db_query "INSERT INTO steps (name, protocol_id, position, created_at, updated_at) VALUES ('Master Mix Preparation', ${PROTOCOL_ID}, 1, NOW(), NOW());"
STEP_ID=$(scinote_db_query "SELECT id FROM steps WHERE name='Master Mix Preparation' AND protocol_id=${PROTOCOL_ID} LIMIT 1;" | tr -d '[:space:]')
echo "${STEP_ID}" > /tmp/step_id

echo "Data created: STEP_ID=${STEP_ID}, ROW_ID=${ROW_ID}"

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

# Wait and capture initial state
sleep 5
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="