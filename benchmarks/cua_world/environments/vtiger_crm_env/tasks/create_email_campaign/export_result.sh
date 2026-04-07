#!/bin/bash
echo "=== Exporting create_email_campaign result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_campaign_count.txt 2>/dev/null || echo "0")

# Take final screenshot for visual verification evidence
take_screenshot /tmp/task_final.png

# Retrieve the target campaign from Vtiger's MariaDB
CAMPAIGN_DATA=$(vtiger_db_query "SELECT c.campaignid, c.campaignname, c.campaigntype, c.campaignstatus, c.expectedrevenue, c.budgetcost, c.targetsize, c.closingdate, UNIX_TIMESTAMP(e.createdtime) FROM vtiger_campaign c INNER JOIN vtiger_crmentity e ON c.campaignid = e.crmid WHERE c.campaignname = 'Summer Clearance 2024' AND e.deleted = 0 LIMIT 1" 2>/dev/null)

CAMPAIGN_FOUND="false"
C_ID="0"
C_TYPE=""
C_STATUS=""
C_REVENUE="0"
C_BUDGET="0"
C_TARGET="0"
C_DATE=""
C_CREATED="0"
CONTACTS_LINKED="0"

if [ -n "$CAMPAIGN_DATA" ]; then
    CAMPAIGN_FOUND="true"
    C_ID=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $1}')
    C_TYPE=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $3}')
    C_STATUS=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $4}')
    C_REVENUE=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $5}')
    C_BUDGET=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $6}')
    C_TARGET=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $7}')
    C_DATE=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $8}')
    C_CREATED=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $9}')

    # Check for linked contacts via the many-to-many relationship tables
    CONTACTS_LINKED=$(vtiger_db_query "SELECT COUNT(DISTINCT contactid) FROM vtiger_campaigncontrel WHERE campaignid = $C_ID" 2>/dev/null | tr -d '[:space:]' || echo "0")
    
    # Fallback checks depending on how Vtiger versions the CRM Entity relations
    if [ -z "$CONTACTS_LINKED" ] || [ "$CONTACTS_LINKED" = "0" ]; then
        CONTACTS_LINKED=$(vtiger_db_query "SELECT COUNT(DISTINCT rel.relcrmid) FROM vtiger_crmentityrel rel INNER JOIN vtiger_crmentity e ON rel.relcrmid = e.crmid WHERE rel.crmid = $C_ID AND e.setype = 'Contacts' AND e.deleted = 0" 2>/dev/null | tr -d '[:space:]' || echo "0")
    fi
    if [ -z "$CONTACTS_LINKED" ] || [ "$CONTACTS_LINKED" = "0" ]; then
        CONTACTS_LINKED=$(vtiger_db_query "SELECT COUNT(DISTINCT rel.crmid) FROM vtiger_crmentityrel rel INNER JOIN vtiger_crmentity e ON rel.crmid = e.crmid WHERE rel.relcrmid = $C_ID AND e.setype = 'Contacts' AND e.deleted = 0" 2>/dev/null | tr -d '[:space:]' || echo "0")
    fi
fi

CURRENT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_campaign" 2>/dev/null | tr -d '[:space:]' || echo "0")

# Create JSON result securely via temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "campaign_found": $CAMPAIGN_FOUND,
    "campaign_id": "$C_ID",
    "campaign_type": "$(json_escape "$C_TYPE")",
    "campaign_status": "$(json_escape "$C_STATUS")",
    "expected_revenue": "$C_REVENUE",
    "budget_cost": "$C_BUDGET",
    "target_size": "$C_TARGET",
    "closing_date": "$(json_escape "$C_DATE")",
    "created_ts": $C_CREATED,
    "contacts_linked": ${CONTACTS_LINKED:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with robust permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="