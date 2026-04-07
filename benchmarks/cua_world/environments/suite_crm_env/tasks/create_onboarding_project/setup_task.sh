#!/bin/bash
echo "=== Setting up create_onboarding_project task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming timestamp)
date +%s > /tmp/task_start_time.txt

# Initial counts
INITIAL_PROJECT_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM project WHERE deleted=0" | tr -d '[:space:]')
INITIAL_TASK_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM project_task WHERE deleted=0" | tr -d '[:space:]')
echo "$INITIAL_PROJECT_COUNT" > /tmp/initial_project_count.txt
echo "$INITIAL_TASK_COUNT" > /tmp/initial_task_count.txt

# Clean state: Remove any existing project with this name and its linked tasks
suitecrm_db_query "UPDATE project_task SET deleted=1 WHERE project_id IN (SELECT id FROM project WHERE name='Greenfield Organics Onboarding')"
suitecrm_db_query "UPDATE project SET deleted=1 WHERE name='Greenfield Organics Onboarding'"

# Ensure user is logged in and navigate to the Projects list view
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Project&action=index"
sleep 3

# Take initial screenshot showing start state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="