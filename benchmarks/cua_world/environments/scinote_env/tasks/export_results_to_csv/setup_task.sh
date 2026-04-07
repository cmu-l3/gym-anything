#!/bin/bash
echo "=== Setting up export_results_to_csv task ==="

# Clean up any potential artifacts from previous runs
rm -f /home/ga/Documents/kinetics_data.csv 2>/dev/null || true
rm -f /tmp/export_task_result.json 2>/dev/null || true
rm -f /tmp/kinetics_data.csv 2>/dev/null || true

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time

source /workspace/scripts/task_utils.sh

# ====================================================================
# Create the SciNote data hierarchy directly in PostgreSQL
# Project -> Experiment -> Task (my_module) -> Result -> ResultTable
# ====================================================================
echo "Provisioning SciNote data (Project, Experiment, Task, Results)..."

# 1. Create Project
scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('Enzyme Characterization', 1, 1, 1, NOW(), NOW(), false, false, false);"
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='Enzyme Characterization' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# 2. Create Experiment
scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('Kinetics Run 1', ${PROJECT_ID}, 1, 1, false, false, NOW(), NOW(), gen_random_uuid());"
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='Kinetics Run 1' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"

# 3. Create Task (my_module)
scinote_db_query "INSERT INTO my_modules (name, x, y, experiment_id, created_at, updated_at, archived, workflow_order, created_by_id) VALUES ('Plate Reader Output', 0, 0, ${EXPERIMENT_ID}, NOW(), NOW(), false, 0, 1);"
TASK_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='Plate Reader Output' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "MyModule" "$TASK_ID"

# 4. Attach empty Protocol (required by SciNote UI to fully render tasks safely)
scinote_db_query "INSERT INTO protocols (name, my_module_id, team_id, protocol_type, created_at, updated_at, archived) VALUES ('Assay Protocol', ${TASK_ID}, 1, 0, NOW(), NOW(), false);"

# 5. Create Result
scinote_db_query "INSERT INTO results (my_module_id, name, created_at, updated_at) VALUES (${TASK_ID}, 'Absorbance Data', NOW(), NOW());"
RESULT_ID=$(scinote_db_query "SELECT id FROM results WHERE my_module_id=${TASK_ID} AND name='Absorbance Data' LIMIT 1;" | tr -d '[:space:]')

# 6. Create ResultTable with the actual scientific data array
DATA_CONTENT='[["Time (min)", "Absorbance (AU)"], ["0", "0.00"], ["5", "0.25"], ["10", "0.45"], ["15", "0.60"], ["30", "0.80"], ["60", "0.95"]]'
scinote_db_query "INSERT INTO result_tables (result_id, content, created_at, updated_at) VALUES (${RESULT_ID}, '${DATA_CONTENT}', NOW(), NOW());"

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="