#!/bin/bash
echo "=== Setting up create_marketing_campaign_contacts task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Record initial campaign count
INITIAL_CAMPAIGN_COUNT=$(vtiger_count "vtiger_campaign")
echo "Initial campaign count: $INITIAL_CAMPAIGN_COUNT"
rm -f /tmp/initial_campaign_count.txt 2>/dev/null || true
echo "$INITIAL_CAMPAIGN_COUNT" > /tmp/initial_campaign_count.txt
chmod 666 /tmp/initial_campaign_count.txt 2>/dev/null || true

# 3. Verify the target campaign does not already exist
EXISTING=$(vtiger_db_query "SELECT campaignid FROM vtiger_campaign WHERE campaignname='CES 2026 VIP Dinner' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING" ]; then
    echo "WARNING: Campaign already exists, removing it to provide a clean state"
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_campaign WHERE campaignid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_campaigncontrel WHERE campaignid=$EXISTING"
fi

# 4. Ensure logged in and navigate to Campaigns list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Campaigns&view=List"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/create_campaign_initial.png

echo "=== create_marketing_campaign_contacts task setup complete ==="
echo "Task: Create campaign 'CES 2026 VIP Dinner' and link 3+ existing contacts."