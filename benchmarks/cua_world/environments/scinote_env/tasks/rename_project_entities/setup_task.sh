#!/bin/bash
set -e

echo "=== Setting up rename_project_entities task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Docker and SciNote are healthy
ensure_docker_healthy
wait_for_scinote_ready 120

# ============================================================
# Create project, experiment, and task with placeholder names
# ============================================================

echo "=== Creating project with placeholder names ==="

# Get team_id and user_id
TEAM_ID=$(scinote_db_query "SELECT id FROM teams LIMIT 1;" | tr -d '[:space:]')
USER_ID=$(scinote_db_query "SELECT id FROM users LIMIT 1;" | tr -d '[:space:]')

echo "Team ID: ${TEAM_ID}, User ID: ${USER_ID}"

# Clean up any existing test projects that might conflict
for PNAME in "Untitled Project" "PET Degradation Kinetics Study"; do
    OLD_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='${PNAME}' AND team_id=${TEAM_ID};" | tr -d '[:space:]')
    if [ -n "$OLD_ID" ]; then
        echo "Removing existing test project '${PNAME}' (ID: ${OLD_ID})..."
        scinote_db_query "DELETE FROM protocols WHERE my_module_id IN (SELECT id FROM my_modules WHERE experiment_id IN (SELECT id FROM experiments WHERE project_id=${OLD_ID}));" || true
        scinote_db_query "DELETE FROM my_modules WHERE experiment_id IN (SELECT id FROM experiments WHERE project_id=${OLD_ID});" || true
        scinote_db_query "DELETE FROM experiments WHERE project_id=${OLD_ID};" || true
        scinote_db_query "DELETE FROM user_assignments WHERE assignable_type='Project' AND assignable_id=${OLD_ID};" || true
        scinote_db_query "DELETE FROM projects WHERE id=${OLD_ID};" || true
    fi
done

# Create the project with deliberately old timestamps so we can detect modification
PROJECT_ID=$(scinote_db_query "INSERT INTO projects (name, visibility, archived, team_id, created_by_id, last_modified_by_id, created_at, updated_at, demo, due_date_notification_sent) VALUES ('Untitled Project', 1, false, ${TEAM_ID}, ${USER_ID}, ${USER_ID}, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', false, false) RETURNING id;" | tr -d '[:space:]')
echo "Created project ID: ${PROJECT_ID}"

if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: Failed to create project!"
    exit 1
fi

# Create user assignment for the project
ensure_user_assignment "Project" "$PROJECT_ID" "$USER_ID" "$TEAM_ID"

# Create the experiment
EXPERIMENT_ID=$(scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, created_at, updated_at, archived, due_date_notification_sent, uuid) VALUES ('Experiment 1', ${PROJECT_ID}, ${USER_ID}, ${USER_ID}, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', false, false, gen_random_uuid()) RETURNING id;" | tr -d '[:space:]')
echo "Created experiment ID: ${EXPERIMENT_ID}"

if [ -z "$EXPERIMENT_ID" ]; then
    echo "ERROR: Failed to create experiment!"
    exit 1
fi

# Create user assignment for the experiment
ensure_user_assignment "Experiment" "$EXPERIMENT_ID" "$USER_ID" "$TEAM_ID"

# Create the task (my_module)
MY_MODULE_ID=$(scinote_db_query "INSERT INTO my_modules (name, experiment_id, created_by_id, last_modified_by_id, created_at, updated_at, x, y, state, archived, workflow_order) VALUES ('Task 1', ${EXPERIMENT_ID}, ${USER_ID}, ${USER_ID}, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', 30, 30, 0, false, 0) RETURNING id;" | tr -d '[:space:]')
echo "Created my_module (task) ID: ${MY_MODULE_ID}"

if [ -z "$MY_MODULE_ID" ]; then
    echo "ERROR: Failed to create task!"
    exit 1
fi

# Create user assignment for the task
ensure_user_assignment "MyModule" "$MY_MODULE_ID" "$USER_ID" "$TEAM_ID"

# Create my_module_group for canvas display (required by SciNote)
GROUP_ID=$(scinote_db_query "INSERT INTO my_module_groups (experiment_id, created_by_id, created_at, updated_at) VALUES (${EXPERIMENT_ID}, ${USER_ID}, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour') RETURNING id;" | tr -d '[:space:]')
if [ -n "$GROUP_ID" ]; then
    scinote_db_query "UPDATE my_modules SET my_module_group_id=${GROUP_ID} WHERE id=${MY_MODULE_ID};" || true
    echo "Created my_module_group ID: ${GROUP_ID}"
fi

# Store IDs for verification
echo "$PROJECT_ID" > /tmp/task_project_id.txt
echo "$EXPERIMENT_ID" > /tmp/task_experiment_id.txt
echo "$MY_MODULE_ID" > /tmp/task_my_module_id.txt

# ============================================================
# Ensure Firefox is running and on the correct page
# ============================================================

echo "=== Ensuring Firefox is on SciNote projects page ==="

# Launch Firefox and focus the SciNote projects page
ensure_firefox_running "${SCINOTE_URL}/projects"

# Wait for page load and take initial screenshot
sleep 4
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Project: 'Untitled Project' (ID: ${PROJECT_ID})"
echo "Experiment: 'Experiment 1' (ID: ${EXPERIMENT_ID})"
echo "Task: 'Task 1' (ID: ${MY_MODULE_ID})"