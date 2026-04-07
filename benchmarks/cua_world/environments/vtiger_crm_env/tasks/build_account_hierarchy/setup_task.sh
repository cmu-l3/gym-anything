#!/bin/bash
echo "=== Setting up build_account_hierarchy task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time and initial maximum CRM ID (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
MAX_CRMID=$(vtiger_db_query "SELECT MAX(crmid) FROM vtiger_crmentity" | tr -d '[:space:]')
rm -f /tmp/initial_max_crmid.txt 2>/dev/null || true
echo "${MAX_CRMID:-0}" > /tmp/initial_max_crmid.txt
chmod 666 /tmp/initial_max_crmid.txt 2>/dev/null || true

# 2. Clean up any existing records with the target names to ensure a clean state
echo "Cleaning up any existing target records..."

# Cleanup Organizations
for ORG in "Apex Global Holdings" "Apex Global - North America" "Apex Global - EMEA"; do
    CRMID=$(vtiger_db_query "SELECT accountid FROM vtiger_account WHERE accountname='$ORG' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$CRMID" ]; then
        echo "Removing existing organization: $ORG (ID: $CRMID)"
        vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$CRMID"
        vtiger_db_query "DELETE FROM vtiger_account WHERE accountid=$CRMID"
        vtiger_db_query "DELETE FROM vtiger_accountbillads WHERE accountaddressid=$CRMID"
        vtiger_db_query "DELETE FROM vtiger_accountshipads WHERE accountaddressid=$CRMID"
    fi
done

# Cleanup Contact
CONTACT_CRMID=$(vtiger_db_query "SELECT contactid FROM vtiger_contactdetails WHERE firstname='Elias' AND lastname='Vance' LIMIT 1" | tr -d '[:space:]')
if [ -n "$CONTACT_CRMID" ]; then
    echo "Removing existing contact: Elias Vance (ID: $CONTACT_CRMID)"
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$CONTACT_CRMID"
    vtiger_db_query "DELETE FROM vtiger_contactdetails WHERE contactid=$CONTACT_CRMID"
    vtiger_db_query "DELETE FROM vtiger_contactaddress WHERE contactaddressid=$CONTACT_CRMID"
    vtiger_db_query "DELETE FROM vtiger_contactsubdetails WHERE contactsubscriptionid=$CONTACT_CRMID"
fi

# 3. Ensure logged in and navigate to Organizations list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Accounts&view=List"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/build_hierarchy_initial.png

echo "=== build_account_hierarchy task setup complete ==="
echo "Agent should start creating the parent organization followed by the subsidiaries and the contact."