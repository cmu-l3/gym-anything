#!/bin/bash
echo "=== Setting up document_pcr_results_smart_annotation task ==="

# Clean up previous task files
rm -f /tmp/document_pcr_results.json 2>/dev/null || true
rm -f /tmp/initial_result_count 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

echo "=== Creating prerequisite project, experiment, and task ==="

# Create project
scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('Genetics Research', 1, 1, 1, NOW(), NOW(), false, false, false);"
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='Genetics Research' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# Create experiment
scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('PCR Optimization', ${PROJECT_ID}, 1, 1, false, false, NOW(), NOW(), gen_random_uuid());"
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='PCR Optimization' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"

# Create task (my_module)
scinote_db_query "INSERT INTO my_modules (name, x, y, experiment_id, created_at, updated_at, archived, workflow_order, created_by_id) VALUES ('PCR Validation', 0, 0, ${EXPERIMENT_ID}, NOW(), NOW(), false, 0, 1);"
TASK_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='PCR Validation' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "MyModule" "$TASK_ID"

echo "=== Creating prerequisite inventory and item ==="

# Create inventory
scinote_db_query "INSERT INTO repositories (name, team_id, created_by_id, created_at, updated_at) VALUES ('Lab Supplies', 1, 1, NOW(), NOW());"
REPO_ID=$(scinote_db_query "SELECT id FROM repositories WHERE name='Lab Supplies' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Repository" "$REPO_ID"

# Create inventory item
scinote_db_query "INSERT INTO repository_rows (name, repository_id, created_by_id, created_at, updated_at) VALUES ('Taq Polymerase', ${REPO_ID}, 1, NOW(), NOW());"

echo "=== Generating sample gel image ==="
mkdir -p /home/ga/Desktop
# Generate a synthetic but realistic looking gel electrophoresis image via ImageMagick
convert -size 400x300 xc:black -fill white -draw "rectangle 50,100 80,110 rectangle 150,150 180,160 rectangle 250,120 280,130 rectangle 350,180 380,190" /home/ga/Desktop/gel_electrophoresis.jpg
chown ga:ga /home/ga/Desktop/gel_electrophoresis.jpg

# Record initial global result count
INITIAL_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM results;" | tr -d '[:space:]')
echo "${INITIAL_COUNT:-0}" > /tmp/initial_result_count
echo "Initial global result count: ${INITIAL_COUNT:-0}"

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="