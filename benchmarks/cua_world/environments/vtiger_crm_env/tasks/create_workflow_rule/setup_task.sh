#!/bin/bash
echo "=== Setting up create_workflow_rule task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming validation)
date +%s > /tmp/task_start_time.txt

# Clean up any existing workflows that might perfectly match the expected output
# This guarantees the agent must actually do the work
MATCHING_WFS=$(vtiger_db_query "SELECT workflow_id FROM com_vtiger_workflows WHERE summary LIKE '%Auto-Update Next Step on Closed Won%'")
for WF_ID in $MATCHING_WFS; do
    if [ -n "$WF_ID" ]; then
        echo "Removing existing matching workflow $WF_ID to ensure clean state"
        vtiger_db_query "DELETE FROM com_vtiger_workflowtasks WHERE workflow_id=$WF_ID"
        vtiger_db_query "DELETE FROM com_vtiger_workflows WHERE workflow_id=$WF_ID"
    fi
done

# Record initial workflow count for Potentials
INITIAL_WF_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM com_vtiger_workflows WHERE module_name='Potentials'" | tr -d '[:space:]')
echo "Initial Potentials workflow count: $INITIAL_WF_COUNT"
rm -f /tmp/initial_wf_count.txt 2>/dev/null || true
echo "$INITIAL_WF_COUNT" > /tmp/initial_wf_count.txt
chmod 666 /tmp/initial_wf_count.txt 2>/dev/null || true

# Ensure logged in and navigate to Potentials list (forcing agent to find the settings)
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Potentials&view=List"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== create_workflow_rule task setup complete ==="