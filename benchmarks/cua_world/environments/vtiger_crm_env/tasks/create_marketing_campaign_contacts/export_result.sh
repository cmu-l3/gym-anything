#!/bin/bash
echo "=== Exporting create_marketing_campaign_contacts results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/create_campaign_final.png

INITIAL_CAMPAIGN_COUNT=$(cat /tmp/initial_campaign_count.txt 2>/dev/null || echo "0")
CURRENT_CAMPAIGN_COUNT=$(vtiger_count "vtiger_campaign")

# Query the campaign and its basic fields, joined with crmentity for description and createdtime
CAMP_DATA=$(vtiger_db_query "SELECT c.campaignid, c.campaigntype, c.campaignstatus, c.expectedrevenue, c.budgetcost, e.description, e.createdtime FROM vtiger_campaign c INNER JOIN vtiger_crmentity e ON c.campaignid = e.crmid WHERE c.campaignname='CES 2026 VIP Dinner' AND e.deleted=0 LIMIT 1")

CAMPAIGN_FOUND="false"
LINKED_CONTACTS=0

if [ -n "$CAMP_DATA" ]; then
    CAMPAIGN_FOUND="true"
    C_ID=$(echo "$CAMP_DATA" | awk -F'\t' '{print $1}')
    C_TYPE=$(echo "$CAMP_DATA" | awk -F'\t' '{print $2}')
    C_STATUS=$(echo "$CAMP_DATA" | awk -F'\t' '{print $3}')
    C_REVENUE=$(echo "$CAMP_DATA" | awk -F'\t' '{print $4}')
    C_BUDGET=$(echo "$CAMP_DATA" | awk -F'\t' '{print $5}')
    C_DESC=$(echo "$CAMP_DATA" | awk -F'\t' '{print $6}')
    C_CREATED=$(echo "$CAMP_DATA" | awk -F'\t' '{print $7}')
    
    # Query linked contacts count
    LINKED_CONTACTS=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_campaigncontrel WHERE campaignid=$C_ID" | tr -d '[:space:]')
fi

# Build JSON safely
RESULT_JSON=$(cat << JSONEOF
{
  "campaign_found": ${CAMPAIGN_FOUND},
  "campaign_id": "$(json_escape "${C_ID:-}")",
  "type": "$(json_escape "${C_TYPE:-}")",
  "status": "$(json_escape "${C_STATUS:-}")",
  "expectedrevenue": "$(json_escape "${C_REVENUE:-}")",
  "budgetcost": "$(json_escape "${C_BUDGET:-}")",
  "description": "$(json_escape "${C_DESC:-}")",
  "createdtime": "$(json_escape "${C_CREATED:-}")",
  "linked_contacts_count": ${LINKED_CONTACTS:-0},
  "initial_count": ${INITIAL_CAMPAIGN_COUNT},
  "current_count": ${CURRENT_CAMPAIGN_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/create_campaign_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_campaign_result.json"
echo "$RESULT_JSON"
echo "=== create_marketing_campaign_contacts export complete ==="