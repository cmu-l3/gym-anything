#!/bin/bash
echo "=== Setting up create_pipeline_report task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing report with the target name to ensure a clean state
EXISTING_REPORT_ID=$(vtiger_db_query "SELECT reportid FROM vtiger_report WHERE reportname='Q4 Pipeline Summary' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_REPORT_ID" ]; then
    echo "WARNING: Target report already exists. Removing to ensure clean state."
    vtiger_db_query "DELETE FROM vtiger_report WHERE reportid=$EXISTING_REPORT_ID"
    vtiger_db_query "DELETE FROM vtiger_reportmodules WHERE reportmodulesid=$EXISTING_REPORT_ID"
    vtiger_db_query "DELETE FROM vtiger_selectcolumn WHERE queryid=$EXISTING_REPORT_ID"
    vtiger_db_query "DELETE FROM vtiger_reportgroupbycolumn WHERE reportid=$EXISTING_REPORT_ID"
    vtiger_db_query "DELETE FROM vtiger_relcriteria WHERE queryid=$EXISTING_REPORT_ID"
    vtiger_db_query "DELETE FROM vtiger_advcriteria WHERE queryid=$EXISTING_REPORT_ID"
fi

# 2. Record initial maximum report ID to verify the new report is actually created during the task
INITIAL_MAX_REPORT_ID=$(vtiger_db_query "SELECT MAX(reportid) FROM vtiger_report" | tr -d '[:space:]')
if [ -z "$INITIAL_MAX_REPORT_ID" ] || [ "$INITIAL_MAX_REPORT_ID" = "NULL" ]; then
    INITIAL_MAX_REPORT_ID=0
fi
echo "Initial Max Report ID: $INITIAL_MAX_REPORT_ID"
echo "$INITIAL_MAX_REPORT_ID" > /tmp/initial_max_report_id.txt

# 3. Ensure Firefox is running, user is logged in, and navigate to the Reports list view
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Reports&view=List"
sleep 5

# 4. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== create_pipeline_report task setup complete ==="
echo "Agent should create a new Summary Report on Potentials named 'Q4 Pipeline Summary'"