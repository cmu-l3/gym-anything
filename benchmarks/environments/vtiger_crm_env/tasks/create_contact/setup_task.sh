#!/bin/bash
echo "=== Setting up create_contact task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record initial contact count
INITIAL_CONTACT_COUNT=$(get_contact_count)
echo "Initial contact count: $INITIAL_CONTACT_COUNT"
rm -f /tmp/initial_contact_count.txt 2>/dev/null || true
echo "$INITIAL_CONTACT_COUNT" > /tmp/initial_contact_count.txt
chmod 666 /tmp/initial_contact_count.txt 2>/dev/null || true

# 2. Verify the target contact does not already exist
if contact_exists "Nathan" "Blackwood"; then
    echo "WARNING: Contact Nathan Blackwood already exists, removing"
    CRMID=$(vtiger_db_query "SELECT contactid FROM vtiger_contactdetails WHERE firstname='Nathan' AND lastname='Blackwood' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$CRMID" ]; then
        vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$CRMID"
        vtiger_db_query "DELETE FROM vtiger_contactdetails WHERE contactid=$CRMID"
        vtiger_db_query "DELETE FROM vtiger_contactaddress WHERE contactaddressid=$CRMID"
        vtiger_db_query "DELETE FROM vtiger_contactsubdetails WHERE contactsubscriptionid=$CRMID"
    fi
fi

# 3. Ensure logged in and navigate to Contacts list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Contacts&view=List"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/create_contact_initial.png

echo "=== create_contact task setup complete ==="
echo "Task: Create a new contact Nathan Blackwood at DataForge Analytics"
echo "Agent should click Add Contact and fill in the form"
