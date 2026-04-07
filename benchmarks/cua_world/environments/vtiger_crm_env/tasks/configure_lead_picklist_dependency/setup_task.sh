#!/bin/bash
echo "=== Setting up Picklist Dependency Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Record initial maximum ID in the dependency table to detect if a new row was actually added
INITIAL_MAX_ID=$(vtiger_db_query "SELECT MAX(id) FROM vtiger_picklist_dependency" | tr -d '[:space:]')
if [ -z "$INITIAL_MAX_ID" ] || [ "$INITIAL_MAX_ID" = "NULL" ]; then
    INITIAL_MAX_ID=0
fi
echo "$INITIAL_MAX_ID" > /tmp/initial_max_id.txt

# Delete any pre-existing dependency configurations for Leads (Industry -> Lead Source) to ensure a clean slate
vtiger_db_query "DELETE p FROM vtiger_picklist_dependency p JOIN vtiger_tab t ON p.tabid = t.tabid WHERE t.name = 'Leads' AND p.sourcefield = 'industry' AND p.targetfield = 'leadsource'"

# Ensure Firefox is open and logged in, starting the agent at the CRM Settings homepage
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Vtiger&parent=Settings&view=Index"
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Picklist Dependency Task Setup Complete ==="