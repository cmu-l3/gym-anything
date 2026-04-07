#!/bin/bash
echo "=== Setting up update_task_statuses task ==="

# Clean up previous task files
rm -f /tmp/update_task_result.json 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

echo "=== Creating prerequisite project, experiment, and tasks ==="

# Create project
PROJ_NAME="Pd-Catalyzed Cross-Coupling Study"
scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('${PROJ_NAME}', 1, 1, 1, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', false, false, false);"
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='${PROJ_NAME}' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"
echo "Created project '${PROJ_NAME}'"

# Create experiment
EXP_NAME="Suzuki Coupling Optimization Run 5"
scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('${EXP_NAME}', ${PROJECT_ID}, 1, 1, false, false, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', gen_random_uuid());"
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='${EXP_NAME}' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"
echo "Created experiment '${EXP_NAME}'"

# Create 5 uncompleted tasks (my_modules with state = 0)
TASKS=("Reagent Preparation" "Reaction Setup" "Reaction Monitoring" "Product Purification" "NMR Analysis")
Y_POS=0
for task_name in "${TASKS[@]}"; do
    scinote_db_query "INSERT INTO my_modules (name, x, y, experiment_id, created_at, updated_at, archived, workflow_order, created_by_id, state) VALUES ('${task_name}', 0, ${Y_POS}, ${EXPERIMENT_ID}, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', false, 0, 1, 0);"
    TASK_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='${task_name}' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')
    ensure_user_assignment "MyModule" "$TASK_ID"
    Y_POS=$((Y_POS + 150))
    echo "Created task '${task_name}' in uncompleted state"
done

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Mark 3 specific tasks as completed in experiment 'Suzuki Coupling Optimization Run 5'"