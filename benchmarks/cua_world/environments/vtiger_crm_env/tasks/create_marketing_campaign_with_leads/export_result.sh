#!/bin/bash
echo "=== Exporting create_marketing_campaign_with_leads results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

DB_START_TIME=$(cat /tmp/db_start_time.txt 2>/dev/null)
INITIAL_LEAD_REL=$(python3 -c "import json; print(json.load(open('/tmp/initial_counts.json')).get('lead_relations', 0))" 2>/dev/null || echo "0")
INITIAL_ORG_REL=$(python3 -c "import json; print(json.load(open('/tmp/initial_counts.json')).get('org_relations', 0))" 2>/dev/null || echo "0")

CURRENT_LEAD_REL=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_campaignleadrel" | tr -d '[:space:]')
CURRENT_ORG_REL=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_campaignaccountrel" | tr -d '[:space:]')

# Query the database for the newly created Campaign
CAMPAIGN_DATA=$(vtiger_db_query "SELECT c.campaignid, c.campaignname, c.campaigntype, c.campaignstatus, c.expectedrevenue, c.budgetcost, e.createdtime FROM vtiger_campaign c INNER JOIN vtiger_crmentity e ON c.campaignid = e.crmid WHERE c.campaignname='Summer End Mega Sale' AND e.deleted=0 LIMIT 1")

CAMPAIGN_FOUND="false"
if [ -n "$CAMPAIGN_DATA" ]; then
    CAMPAIGN_FOUND="true"
    C_ID=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $1}')
    C_NAME=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $2}')
    C_TYPE=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $3}')
    C_STATUS=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $4}')
    C_REV=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $5}')
    C_COST=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $6}')
    C_CREATED=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $7}')
    
    # Get specific relations for this campaign
    LINKED_LEADS=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_campaignleadrel WHERE campaignid=$C_ID" | tr -d '[:space:]')
    LINKED_ORGS=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_campaignaccountrel WHERE campaignid=$C_ID" | tr -d '[:space:]')
else
    C_ID=""
    C_NAME=""
    C_TYPE=""
    C_STATUS=""
    C_REV="0"
    C_COST="0"
    C_CREATED=""
    LINKED_LEADS="0"
    LINKED_ORGS="0"
fi

RESULT_JSON=$(cat << JSONEOF
{
  "campaign_found": ${CAMPAIGN_FOUND},
  "campaign_id": "$(json_escape "${C_ID:-}")",
  "name": "$(json_escape "${C_NAME:-}")",
  "type": "$(json_escape "${C_TYPE:-}")",
  "status": "$(json_escape "${C_STATUS:-}")",
  "expected_revenue": "$(json_escape "${C_REV:-}")",
  "budget_cost": "$(json_escape "${C_COST:-}")",
  "created_time": "$(json_escape "${C_CREATED:-}")",
  "db_start_time": "$(json_escape "${DB_START_TIME:-}")",
  "linked_leads_count": ${LINKED_LEADS:-0},
  "linked_orgs_count": ${LINKED_ORGS:-0},
  "global_initial_lead_rel": ${INITIAL_LEAD_REL:-0},
  "global_initial_org_rel": ${INITIAL_ORG_REL:-0},
  "global_current_lead_rel": ${CURRENT_LEAD_REL:-0},
  "global_current_org_rel": ${CURRENT_ORG_REL:-0}
}
JSONEOF
)

safe_write_result "/tmp/campaign_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/campaign_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="