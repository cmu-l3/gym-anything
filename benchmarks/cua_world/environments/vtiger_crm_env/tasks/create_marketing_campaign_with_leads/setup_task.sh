#!/bin/bash
echo "=== Setting up create_marketing_campaign_with_leads task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Record DB start time for anti-gaming checks
DB_START_TIME=$(vtiger_db_query "SELECT NOW()" | tr -d '\t\n\r')
echo "$DB_START_TIME" > /tmp/db_start_time.txt

# Remove existing campaign if it exists to ensure a clean state
EXISTING=$(vtiger_db_query "SELECT campaignid FROM vtiger_campaign WHERE campaignname='Summer End Mega Sale' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING" ]; then
    echo "Removing existing campaign to ensure clean state..."
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_campaign WHERE campaignid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_campaignleadrel WHERE campaignid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_campaignaccountrel WHERE campaignid=$EXISTING"
fi

# Record initial global relationship counts for anti-gaming (to ensure new links are actually made)
INITIAL_LEAD_REL=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_campaignleadrel" | tr -d '[:space:]')
INITIAL_ORG_REL=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_campaignaccountrel" | tr -d '[:space:]')
echo "Initial global lead relations: $INITIAL_LEAD_REL"
echo "Initial global org relations: $INITIAL_ORG_REL"

cat > /tmp/initial_counts.json << EOF
{
  "lead_relations": ${INITIAL_LEAD_REL:-0},
  "org_relations": ${INITIAL_ORG_REL:-0}
}
EOF
chmod 666 /tmp/initial_counts.json 2>/dev/null || true

# Navigate to Campaigns view
echo "Ensuring user is logged in and on the Campaigns list view..."
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Campaigns&view=List"
sleep 3

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="