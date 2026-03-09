#!/bin/bash
# Setup script for client_onboarding_full_setup task
# Ensures a clean state for ClearSky Aerospace Technologies and records baselines.

echo "=== Setting up client_onboarding_full_setup task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/onboarding_start_ts

# ---------------------------------------------------------------
# Ensure ClearSky does NOT already exist (idempotent cleanup)
# ---------------------------------------------------------------
EXISTING_ORG=$(vtiger_db_query "SELECT accountid FROM vtiger_account WHERE accountname='ClearSky Aerospace Technologies' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_ORG" ]; then
    echo "Removing pre-existing ClearSky org (id=$EXISTING_ORG)"
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING_ORG" 2>/dev/null || true
    vtiger_db_query "DELETE FROM vtiger_account WHERE accountid=$EXISTING_ORG" 2>/dev/null || true
    vtiger_db_query "DELETE FROM vtiger_accountbillads WHERE accountaddressid=$EXISTING_ORG" 2>/dev/null || true
fi

# Ensure Harrison Yates contact does not exist
for NAME in "Harrison Yates" "Priya Natarajan"; do
    FIRST=$(echo "$NAME" | cut -d' ' -f1)
    LAST=$(echo "$NAME" | cut -d' ' -f2)
    EXISTING_CONTACT=$(vtiger_db_query "SELECT contactid FROM vtiger_contactdetails WHERE firstname='$FIRST' AND lastname='$LAST' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$EXISTING_CONTACT" ]; then
        echo "Removing pre-existing contact $NAME (id=$EXISTING_CONTACT)"
        vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING_CONTACT" 2>/dev/null || true
        vtiger_db_query "DELETE FROM vtiger_contactdetails WHERE contactid=$EXISTING_CONTACT" 2>/dev/null || true
    fi
done

# Remove any existing ClearSky deal
vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid IN (SELECT potentialid FROM vtiger_potential WHERE potentialname='ClearSky Zero-Trust Security Implementation')" 2>/dev/null || true
vtiger_db_query "DELETE FROM vtiger_potential WHERE potentialname='ClearSky Zero-Trust Security Implementation'" 2>/dev/null || true

# Remove any existing onboarding kickoff event
vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid IN (SELECT activityid FROM vtiger_activity WHERE subject LIKE '%ClearSky%Kickoff%')" 2>/dev/null || true
vtiger_db_query "DELETE FROM vtiger_activity WHERE subject LIKE '%ClearSky%Kickoff%'" 2>/dev/null || true

# Record baselines
echo "$(get_org_count)" > /tmp/onboarding_initial_org_count
echo "$(get_contact_count)" > /tmp/onboarding_initial_contact_count
echo "$(get_deal_count)" > /tmp/onboarding_initial_deal_count
echo "$(get_event_count)" > /tmp/onboarding_initial_event_count

# Navigate agent to Organizations list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Accounts&view=List"
sleep 3

take_screenshot /tmp/onboarding_start.png

echo "=== Setup Complete ==="
echo "Agent must create: 1 organization, 2 contacts, 1 deal, 1 meeting event for ClearSky Aerospace Technologies."
