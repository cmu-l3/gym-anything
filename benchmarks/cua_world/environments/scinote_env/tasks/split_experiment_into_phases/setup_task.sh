#!/bin/bash
echo "=== Setting up split_experiment_into_phases task ==="

rm -f /tmp/split_experiment_result.json 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true

source /workspace/scripts/task_utils.sh

echo "=== Creating prerequisite project, experiment, and tasks ==="

# Create project
scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('Cell Line Development', 1, 1, 1, NOW(), NOW(), false, false, false);"
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='Cell Line Development' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# Create experiment
scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('Transfection Workflow', ${PROJECT_ID}, 1, 1, false, false, NOW(), NOW(), gen_random_uuid());"
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='Transfection Workflow' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"

# Create a module group for the experiment
scinote_db_query "INSERT INTO my_module_groups (experiment_id, user_id, created_at, updated_at) VALUES (${EXPERIMENT_ID}, 1, NOW(), NOW());"
GROUP_ID=$(scinote_db_query "SELECT id FROM my_module_groups WHERE experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')

# Create tasks
TASKS=("Media Prep" "Cell Seeding" "Transfection Mix" "Incubation" "Selection" "Expansion")
X=0
for TASK in "${TASKS[@]}"; do
    scinote_db_query "INSERT INTO my_modules (name, x, y, experiment_id, my_module_group_id, created_at, updated_at, archived, workflow_order, created_by_id) VALUES ('$TASK', $X, 0, ${EXPERIMENT_ID}, ${GROUP_ID}, NOW(), NOW(), false, 0, 1);"
    TASK_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='$TASK' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')
    ensure_user_assignment "MyModule" "$TASK_ID"
    scinote_db_query "INSERT INTO protocols (my_module_id, team_id, protocol_type, created_at, updated_at, archived) VALUES (${TASK_ID}, 1, 0, NOW(), NOW(), false);"
    X=$((X + 300))
done

# Save original experiment id
echo "$EXPERIMENT_ID" > /tmp/original_experiment_id

# Ensure Firefox is running and user is at login
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

# Record task start time strictly AFTER database insertions for anti-gaming checks
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="