#!/bin/bash
echo "=== Setting up create_followup_task task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Clean up any pre-existing task with the same subject from prior attempts
echo "Cleaning up any existing matching tasks..."
suitecrm_db_query "UPDATE tasks SET deleted=1 WHERE name='Prepare Proposal for Meridian Retail Group' AND deleted=0" || true
suitecrm_db_query "UPDATE tasks SET deleted=1 WHERE name LIKE '%Meridian Retail%' AND deleted=0" || true

# 2. Record initial task count AFTER cleanup
INITIAL_TASK_COUNT=$(suitecrm_count "tasks" "deleted=0")
echo "Initial task count: $INITIAL_TASK_COUNT"
rm -f /tmp/initial_task_count.txt 2>/dev/null || true
echo "$INITIAL_TASK_COUNT" > /tmp/initial_task_count.txt
chmod 666 /tmp/initial_task_count.txt 2>/dev/null || true

# 3. Ensure logged in and navigate to Home dashboard
# The agent needs to navigate to Tasks from the dashboard
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== create_followup_task setup complete ==="
echo "Task: Create a new follow-up task for Meridian Retail Group"