#!/bin/bash
echo "=== Setting up schedule_weekly_lead_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Record initial max report id to prevent gaming
INITIAL_REPORT_MAX_ID=$(vtiger_db_query "SELECT MAX(reportid) FROM vtiger_report" | tr -d '[:space:]')
INITIAL_REPORT_MAX_ID=${INITIAL_REPORT_MAX_ID:-0}
echo "Initial max report ID: $INITIAL_REPORT_MAX_ID"
rm -f /tmp/initial_report_max_id.txt 2>/dev/null || true
echo "$INITIAL_REPORT_MAX_ID" > /tmp/initial_report_max_id.txt
chmod 666 /tmp/initial_report_max_id.txt 2>/dev/null || true

# 2. Verify the target report does not already exist
EXISTING=$(vtiger_db_query "SELECT reportid FROM vtiger_report WHERE reportname='Weekly Lead Source Summary' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING" ]; then
    echo "WARNING: Report already exists, removing it for clean state"
    vtiger_db_query "DELETE FROM vtiger_report WHERE reportid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_reportsortcol WHERE reportid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_reportgroupbycolumn WHERE reportid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_scheduled_reports WHERE reportid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_reportmodules WHERE reportmodulesid=$EXISTING"
fi

# 3. Ensure logged in and navigate to Reports list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Reports&view=List"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/schedule_report_initial.png

echo "=== schedule_weekly_lead_report task setup complete ==="
echo "Task: Create and schedule 'Weekly Lead Source Summary' report"