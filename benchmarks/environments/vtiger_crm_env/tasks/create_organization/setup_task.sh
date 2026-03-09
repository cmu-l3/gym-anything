#!/bin/bash
echo "=== Setting up create_organization task ==="

source /workspace/scripts/task_utils.sh

# 1. Record initial org count
INITIAL_ORG_COUNT=$(get_org_count)
echo "Initial organization count: $INITIAL_ORG_COUNT"
rm -f /tmp/initial_org_count.txt 2>/dev/null || true
echo "$INITIAL_ORG_COUNT" > /tmp/initial_org_count.txt
chmod 666 /tmp/initial_org_count.txt 2>/dev/null || true

# 2. Verify target org does not already exist
if org_exists "Redwood Consulting Partners"; then
    echo "WARNING: Organization already exists, removing"
    CRMID=$(vtiger_db_query "SELECT accountid FROM vtiger_account WHERE accountname='Redwood Consulting Partners' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$CRMID" ]; then
        vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$CRMID"
        vtiger_db_query "DELETE FROM vtiger_account WHERE accountid=$CRMID"
        vtiger_db_query "DELETE FROM vtiger_accountbillads WHERE accountaddressid=$CRMID"
        vtiger_db_query "DELETE FROM vtiger_accountshipads WHERE accountaddressid=$CRMID"
    fi
fi

# 3. Ensure logged in and navigate to Organizations list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Accounts&view=List"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/create_organization_initial.png

echo "=== create_organization task setup complete ==="
echo "Task: Create organization Redwood Consulting Partners"
echo "Agent should click Add Organization and fill in the form"
