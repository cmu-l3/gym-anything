#!/bin/bash
echo "=== Setting up add_picklist_values task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean up any existing target values to ensure a perfectly clean initial state
echo "Cleaning up any pre-existing custom picklist values..."

# Clean Lead Source values
LS_SM_ID=$(vtiger_db_query "SELECT picklist_valueid FROM vtiger_leadsource WHERE leadsource='Social Media'" | tr -d '[:space:]')
if [ -n "$LS_SM_ID" ]; then
    vtiger_db_query "DELETE FROM vtiger_role2picklist WHERE picklistvalueid='$LS_SM_ID'"
    vtiger_db_query "DELETE FROM vtiger_leadsource WHERE picklist_valueid='$LS_SM_ID'"
fi

LS_RP_ID=$(vtiger_db_query "SELECT picklist_valueid FROM vtiger_leadsource WHERE leadsource='Referral Program'" | tr -d '[:space:]')
if [ -n "$LS_RP_ID" ]; then
    vtiger_db_query "DELETE FROM vtiger_role2picklist WHERE picklistvalueid='$LS_RP_ID'"
    vtiger_db_query "DELETE FROM vtiger_leadsource WHERE picklist_valueid='$LS_RP_ID'"
fi

# Clean Industry values
IND_LS_ID=$(vtiger_db_query "SELECT picklist_valueid FROM vtiger_industry WHERE industry='Landscaping Services'" | tr -d '[:space:]')
if [ -n "$IND_LS_ID" ]; then
    vtiger_db_query "DELETE FROM vtiger_role2picklist WHERE picklistvalueid='$IND_LS_ID'"
    vtiger_db_query "DELETE FROM vtiger_industry WHERE picklist_valueid='$IND_LS_ID'"
fi

IND_PM_ID=$(vtiger_db_query "SELECT picklist_valueid FROM vtiger_industry WHERE industry='Property Management'" | tr -d '[:space:]')
if [ -n "$IND_PM_ID" ]; then
    vtiger_db_query "DELETE FROM vtiger_role2picklist WHERE picklistvalueid='$IND_PM_ID'"
    vtiger_db_query "DELETE FROM vtiger_industry WHERE picklist_valueid='$IND_PM_ID'"
fi

# Ensure logged in and navigate to dashboard as starting point
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# Take initial screenshot
take_screenshot /tmp/add_picklist_initial.png

echo "=== add_picklist_values task setup complete ==="
echo "Task: Add custom picklist values for Lead Source and Industry fields."