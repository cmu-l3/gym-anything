#!/bin/bash
echo "=== Exporting add_picklist_values results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/add_picklist_final.png

# Query for Social Media in Lead Source
SM_EXISTS="false"
SM_ROLE="false"
SM_ID=$(vtiger_db_query "SELECT picklist_valueid FROM vtiger_leadsource WHERE leadsource='Social Media'" | tr -d '[:space:]')
if [ -n "$SM_ID" ]; then
    SM_EXISTS="true"
    ROLE_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_role2picklist WHERE picklistvalueid='$SM_ID'" | tr -d '[:space:]')
    if [ "$ROLE_COUNT" -gt 0 ]; then
        SM_ROLE="true"
    fi
fi

# Query for Referral Program in Lead Source
RP_EXISTS="false"
RP_ROLE="false"
RP_ID=$(vtiger_db_query "SELECT picklist_valueid FROM vtiger_leadsource WHERE leadsource='Referral Program'" | tr -d '[:space:]')
if [ -n "$RP_ID" ]; then
    RP_EXISTS="true"
    ROLE_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_role2picklist WHERE picklistvalueid='$RP_ID'" | tr -d '[:space:]')
    if [ "$ROLE_COUNT" -gt 0 ]; then
        RP_ROLE="true"
    fi
fi

# Query for Landscaping Services in Industry
LS_EXISTS="false"
LS_ROLE="false"
LS_ID=$(vtiger_db_query "SELECT picklist_valueid FROM vtiger_industry WHERE industry='Landscaping Services'" | tr -d '[:space:]')
if [ -n "$LS_ID" ]; then
    LS_EXISTS="true"
    ROLE_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_role2picklist WHERE picklistvalueid='$LS_ID'" | tr -d '[:space:]')
    if [ "$ROLE_COUNT" -gt 0 ]; then
        LS_ROLE="true"
    fi
fi

# Query for Property Management in Industry
PM_EXISTS="false"
PM_ROLE="false"
PM_ID=$(vtiger_db_query "SELECT picklist_valueid FROM vtiger_industry WHERE industry='Property Management'" | tr -d '[:space:]')
if [ -n "$PM_ID" ]; then
    PM_EXISTS="true"
    ROLE_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_role2picklist WHERE picklistvalueid='$PM_ID'" | tr -d '[:space:]')
    if [ "$ROLE_COUNT" -gt 0 ]; then
        PM_ROLE="true"
    fi
fi

# Build output JSON
RESULT_JSON=$(cat << JSONEOF
{
  "social_media": {
    "exists": $SM_EXISTS,
    "role_mapped": $SM_ROLE
  },
  "referral_program": {
    "exists": $RP_EXISTS,
    "role_mapped": $RP_ROLE
  },
  "landscaping_services": {
    "exists": $LS_EXISTS,
    "role_mapped": $LS_ROLE
  },
  "property_management": {
    "exists": $PM_EXISTS,
    "role_mapped": $PM_ROLE
  },
  "timestamp": "$(date +%s)"
}
JSONEOF
)

safe_write_result "/tmp/add_picklist_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/add_picklist_result.json"
cat /tmp/add_picklist_result.json
echo "=== add_picklist_values export complete ==="