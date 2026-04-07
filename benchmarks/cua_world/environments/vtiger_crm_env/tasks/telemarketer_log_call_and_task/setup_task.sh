#!/bin/bash
echo "=== Setting up telemarketer_log_call_and_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any existing records that match the target to prevent false positives
echo "Cleaning up any pre-existing matching records..."
EXISTING_LEAD=$(vtiger_db_query "SELECT leadid FROM vtiger_leaddetails WHERE firstname='David' AND lastname='Miller' AND company='Maersk Logistics' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_LEAD" ]; then
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING_LEAD"
    vtiger_db_query "DELETE FROM vtiger_leaddetails WHERE leadid=$EXISTING_LEAD"
fi

vtiger_db_query "DELETE FROM vtiger_crmentity WHERE label IN ('Initial Discovery Call', 'Send Maersk Pricing Deck')"
vtiger_db_query "DELETE FROM vtiger_activity WHERE subject IN ('Initial Discovery Call', 'Send Maersk Pricing Deck')"

# Ensure Firefox is running, logged into Vtiger CRM, and on the Leads list view
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Leads&view=List"
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="