#!/bin/bash
echo "=== Setting up create_email_campaign task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Record initial campaign count
INITIAL_CAMPAIGN_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_campaign" 2>/dev/null | tr -d '[:space:]' || echo "0")
echo "$INITIAL_CAMPAIGN_COUNT" > /tmp/initial_campaign_count.txt
echo "Initial campaign count: $INITIAL_CAMPAIGN_COUNT"

# Delete any pre-existing campaign named "Summer Clearance 2024" to ensure clean state
EXISTING_ID=$(vtiger_db_query "SELECT c.campaignid FROM vtiger_campaign c INNER JOIN vtiger_crmentity e ON c.campaignid = e.crmid WHERE c.campaignname = 'Summer Clearance 2024' AND e.deleted = 0 LIMIT 1" 2>/dev/null | tr -d '[:space:]')
if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "0" ]; then
    echo "Removing pre-existing campaign (ID: $EXISTING_ID)..."
    vtiger_db_query "UPDATE vtiger_crmentity SET deleted = 1 WHERE crmid = $EXISTING_ID" 2>/dev/null || true
    vtiger_db_query "DELETE FROM vtiger_campaigncontrel WHERE campaignid = $EXISTING_ID" 2>/dev/null || true
fi

# Verify contacts exist for linking
CONTACT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_contactdetails cd INNER JOIN vtiger_crmentity e ON cd.contactid = e.crmid WHERE e.deleted = 0" 2>/dev/null | tr -d '[:space:]' || echo "0")
echo "Available contacts for linking: $CONTACT_COUNT"

# Ensure Firefox is open and logged into Vtiger CRM Campaigns view
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Campaigns&view=List"
sleep 5

# Maximize and focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="