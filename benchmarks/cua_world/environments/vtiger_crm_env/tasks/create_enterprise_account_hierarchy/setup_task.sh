#!/bin/bash
echo "=== Setting up create_enterprise_account_hierarchy task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# Clean up any pre-existing records that match our target names to ensure a clean state
echo "Cleaning up pre-existing records (if any)..."

# 1. Deals
EXISTING_DEAL=$(vtiger_db_query "SELECT potentialid FROM vtiger_potential WHERE potentialname='Q4 2026 Commercial Aviation Parts Contract'")
for id in $EXISTING_DEAL; do
    if [ -n "$id" ]; then
        vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$id"
        vtiger_db_query "DELETE FROM vtiger_potential WHERE potentialid=$id"
    fi
done

# 2. Contacts
for lname in "Wagner" "Tanaka"; do
    EXISTING_CONTACT=$(vtiger_db_query "SELECT contactid FROM vtiger_contactdetails WHERE lastname='$lname'")
    for id in $EXISTING_CONTACT; do
        if [ -n "$id" ]; then
            vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$id"
            vtiger_db_query "DELETE FROM vtiger_contactdetails WHERE contactid=$id"
            vtiger_db_query "DELETE FROM vtiger_contactaddress WHERE contactaddressid=$id"
            vtiger_db_query "DELETE FROM vtiger_contactsubdetails WHERE contactsubscriptionid=$id"
        fi
    done
done

# 3. Organizations
for orgname in "AeroTech Dynamics Global HQ" "AeroTech Dynamics GmbH" "AeroTech Dynamics KK"; do
    EXISTING_ORG=$(vtiger_db_query "SELECT accountid FROM vtiger_account WHERE accountname='$orgname'")
    for id in $EXISTING_ORG; do
        if [ -n "$id" ]; then
            vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$id"
            vtiger_db_query "DELETE FROM vtiger_account WHERE accountid=$id"
            vtiger_db_query "DELETE FROM vtiger_accountbillads WHERE accountaddressid=$id"
            vtiger_db_query "DELETE FROM vtiger_accountshipads WHERE accountaddressid=$id"
        fi
    done
done

# Ensure logged in and navigate to the Organizations list (a good starting point)
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Accounts&view=List"
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="