#!/bin/bash
echo "=== Setting up create_experiment task ==="

# Clean up previous task files
rm -f /tmp/create_experiment_result.json 2>/dev/null || true
rm -f /tmp/initial_experiment_count 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create prerequisite project 'Drug Discovery Pipeline' via SQL
echo "=== Creating prerequisite project 'Drug Discovery Pipeline' ==="
EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM projects WHERE name='Drug Discovery Pipeline';" | tr -d '[:space:]')
if [ "${EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('Drug Discovery Pipeline', 1, 1, 1, NOW(), NOW(), false, false, false);"
    echo "Created project 'Drug Discovery Pipeline'"
else
    echo "Project 'Drug Discovery Pipeline' already exists"
fi
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='Drug Discovery Pipeline' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# Record initial experiment count
INITIAL_COUNT=$(get_experiment_count)
echo "${INITIAL_COUNT:-0}" > /tmp/initial_experiment_count
echo "Initial experiment count: ${INITIAL_COUNT:-0}"

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Create experiment 'HPLC Analysis Run 3' in project 'Drug Discovery Pipeline'"
