#!/bin/bash
echo "=== Setting up create_workflow_rule task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial workflow count
INITIAL_WF_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aow_workflow WHERE deleted=0" | tr -d '[:space:]')
echo "$INITIAL_WF_COUNT" > /tmp/initial_workflow_count.txt
echo "Initial workflow count: $INITIAL_WF_COUNT"

# Clean up any existing workflow with the target name (from previous testing)
suitecrm_db_query "UPDATE aow_workflow SET deleted=1 WHERE name LIKE '%Auto-Qualify High-Value Prospects%'"
suitecrm_db_query "UPDATE aow_conditions SET deleted=1 WHERE aow_workflow_id IN (SELECT id FROM aow_workflow WHERE deleted=1)"
suitecrm_db_query "UPDATE aow_actions SET deleted=1 WHERE aow_workflow_id IN (SELECT id FROM aow_workflow WHERE deleted=1)"

# Ensure logged in and navigate to SuiteCRM home
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent must navigate to Workflow module and create the automation rule."