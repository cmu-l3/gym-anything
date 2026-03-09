#!/bin/bash
echo "=== Setting up create_deal task ==="

source /workspace/scripts/task_utils.sh

# 1. Record initial deal count
INITIAL_DEAL_COUNT=$(get_deal_count)
echo "Initial deal count: $INITIAL_DEAL_COUNT"
rm -f /tmp/initial_deal_count.txt 2>/dev/null || true
echo "$INITIAL_DEAL_COUNT" > /tmp/initial_deal_count.txt
chmod 666 /tmp/initial_deal_count.txt 2>/dev/null || true

# 2. Verify the target deal does not already exist
EXISTING=$(vtiger_db_query "SELECT potentialid FROM vtiger_potential WHERE potentialname='DataForge Enterprise Analytics Rollout' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING" ]; then
    echo "WARNING: Deal already exists, removing"
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_potential WHERE potentialid=$EXISTING"
fi

# 3. Ensure logged in and navigate to Deals list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Potentials&view=List"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/create_deal_initial.png

echo "=== create_deal task setup complete ==="
echo "Task: Create deal 'DataForge Enterprise Analytics Rollout'"
echo "Agent should click Add Deal/Opportunity and fill in the form"
