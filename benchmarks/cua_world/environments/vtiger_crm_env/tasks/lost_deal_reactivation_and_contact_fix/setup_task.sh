#!/bin/bash
# Setup script for lost_deal_reactivation_and_contact_fix task

echo "=== Setting up lost_deal_reactivation_and_contact_fix ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/ironshield_start_ts

# -----------------------------------------------------------------------
# 1. Corrupt the IronShield Network Hardening deal:
#    - Mark as Closed Lost with wrong probability and stale data
# -----------------------------------------------------------------------
echo "Corrupting IronShield deal to Closed Lost..."
vtiger_db_query "UPDATE vtiger_potential SET sales_stage='Closed Lost', probability='0', closingdate='2025-12-31', amount='175000' WHERE potentialname='IronShield Network Hardening'"

# -----------------------------------------------------------------------
# 2. Corrupt Victoria Blackwell's contact: clear email and title
# -----------------------------------------------------------------------
echo "Clearing Victoria Blackwell email and title..."
CONTACT_ID_VB=$(vtiger_db_query "SELECT contactid FROM vtiger_contactdetails WHERE firstname='Victoria' AND lastname='Blackwell' LIMIT 1" | tr -d '[:space:]')
if [ -n "$CONTACT_ID_VB" ]; then
    vtiger_db_query "UPDATE vtiger_contactdetails SET email='', title='' WHERE contactid='$CONTACT_ID_VB'"
else
    echo "WARNING: Victoria Blackwell not found in DB — seeding may be needed"
fi

# -----------------------------------------------------------------------
# 3. Corrupt Thomas Park's contact: clear phone and title
# -----------------------------------------------------------------------
echo "Clearing Thomas Park phone and title..."
CONTACT_ID_TP=$(vtiger_db_query "SELECT contactid FROM vtiger_contactdetails WHERE firstname='Thomas' AND lastname='Park' LIMIT 1" | tr -d '[:space:]')
if [ -n "$CONTACT_ID_TP" ]; then
    vtiger_db_query "UPDATE vtiger_contactdetails SET phone='', title='' WHERE contactid='$CONTACT_ID_TP'"
else
    echo "WARNING: Thomas Park not found in DB — seeding may be needed"
fi

# -----------------------------------------------------------------------
# 4. Clean up any pre-existing IronShield reactivation call events
# -----------------------------------------------------------------------
echo "Removing any pre-existing IronShield reactivation call..."
OLD_EVENT=$(vtiger_db_query "SELECT activityid FROM vtiger_activity WHERE subject LIKE '%IronShield%Reactivation%' OR subject LIKE '%Blackstone%IronShield%' LIMIT 1" | tr -d '[:space:]')
if [ -n "$OLD_EVENT" ]; then
    vtiger_db_query "DELETE FROM vtiger_activity WHERE activityid='$OLD_EVENT'"
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid='$OLD_EVENT'"
fi

# -----------------------------------------------------------------------
# 5. Record baseline counts
# -----------------------------------------------------------------------
echo $(vtiger_db_query "SELECT COUNT(*) FROM vtiger_activity WHERE activitytype='Call'" | tr -d '[:space:]') > /tmp/ironshield_baseline_call_count

# -----------------------------------------------------------------------
# 6. Navigate agent to Deals list to begin task
# -----------------------------------------------------------------------
ensure_vtiger_logged_in
WID=$(get_slicer_window_id 2>/dev/null || xdotool search --name "vtiger" | head -1)
if [ -n "$WID" ]; then
    xdotool windowactivate --sync "$WID" 2>/dev/null || true
fi

take_screenshot /tmp/ironshield_setup_done.png

echo "=== Setup complete: IronShield deal marked Closed Lost, contact fields cleared ==="
