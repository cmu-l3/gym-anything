#!/bin/bash
echo "=== Setting up create_custom_listview task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare realistic data: Ensure some contacts are in New York
echo "Seeding 'New York' location data for contacts..."
vtiger_db_query "UPDATE vtiger_contactaddress SET mailingcity = 'New York', mailingstate = 'NY', mailingcountry = 'United States' WHERE contactaddressid IN (SELECT contactid FROM vtiger_contactdetails ORDER BY contactid LIMIT 5);"
vtiger_db_query "UPDATE vtiger_contactaddress SET mailingcity = 'Chicago', mailingstate = 'IL' WHERE contactaddressid IN (SELECT contactid FROM vtiger_contactdetails ORDER BY contactid LIMIT 5 OFFSET 5);"

# 2. Clean up any existing views with the target name to ensure a clean state
EXISTING_CVID=$(vtiger_db_query "SELECT cvid FROM vtiger_customview WHERE viewname='New York Contacts' AND entitytype='Contacts' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_CVID" ]; then
    echo "WARNING: Target custom view already exists. Cleaning up (cvid: $EXISTING_CVID)..."
    vtiger_db_query "DELETE FROM vtiger_cvadvfilter WHERE cvid=$EXISTING_CVID"
    vtiger_db_query "DELETE FROM vtiger_cvcolumnlist WHERE cvid=$EXISTING_CVID"
    vtiger_db_query "DELETE FROM vtiger_customview WHERE cvid=$EXISTING_CVID"
fi

# 3. Record the maximum custom view ID before the task starts (Anti-Gaming)
MAX_CVID=$(vtiger_db_query "SELECT MAX(cvid) FROM vtiger_customview" | tr -d '[:space:]')
if [ -z "$MAX_CVID" ] || [ "$MAX_CVID" == "NULL" ]; then
    MAX_CVID=0
fi
echo "Initial max cvid: $MAX_CVID"
rm -f /tmp/initial_max_cvid.txt 2>/dev/null || true
echo "$MAX_CVID" > /tmp/initial_max_cvid.txt
chmod 666 /tmp/initial_max_cvid.txt 2>/dev/null || true

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Ensure Firefox is logged in and navigated to the Contacts module
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Contacts&view=List"
sleep 3

# 6. Take initial screenshot as evidence of starting state
take_screenshot /tmp/create_custom_listview_initial.png

echo "=== create_custom_listview task setup complete ==="
echo "Task: Create a custom filtered list view for Contacts in New York"
echo "Agent should interact with the list view creation UI"