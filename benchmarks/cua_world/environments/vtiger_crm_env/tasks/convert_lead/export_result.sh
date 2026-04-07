#!/bin/bash
set -e
echo "=== Exporting Convert Lead results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve initial counts
INITIAL_CONTACT_COUNT=$(cat /tmp/initial_contact_count.txt 2>/dev/null || echo "0")
INITIAL_ORG_COUNT=$(cat /tmp/initial_org_count.txt 2>/dev/null || echo "0")
INITIAL_POT_COUNT=$(cat /tmp/initial_pot_count.txt 2>/dev/null || echo "0")

# 1. Lead Converted Status
LEAD_CONVERTED=$(vtiger_db_query "SELECT ld.converted FROM vtiger_leaddetails ld INNER JOIN vtiger_crmentity ce ON ce.crmid=ld.leadid WHERE ld.firstname='Patricia' AND ld.lastname='Hernandez' ORDER BY ld.leadid DESC LIMIT 1" | tr -d '[:space:]')

# 2. Contact Exists
CONTACT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_contactdetails cd INNER JOIN vtiger_crmentity ce ON ce.crmid=cd.contactid WHERE cd.firstname='Patricia' AND cd.lastname='Hernandez' AND ce.deleted=0" | tr -d '[:space:]')

# 3. Organization Exists
ORG_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_account a INNER JOIN vtiger_crmentity ce ON ce.crmid=a.accountid WHERE a.accountname='Summit Industrial Supplies' AND ce.deleted=0" | tr -d '[:space:]')

# 4. Opportunity Details
POT_DATA=$(vtiger_db_query "SELECT p.potentialname, p.amount, p.sales_stage FROM vtiger_potential p INNER JOIN vtiger_crmentity ce ON ce.crmid=p.potentialid WHERE p.potentialname LIKE '%Summit Industrial%' AND ce.deleted=0 ORDER BY p.potentialid DESC LIMIT 1")

POT_EXISTS="false"
P_NAME=""
P_AMOUNT=""
P_STAGE=""

if [ -n "$POT_DATA" ]; then
    POT_EXISTS="true"
    P_NAME=$(echo "$POT_DATA" | awk -F'\t' '{print $1}')
    P_AMOUNT=$(echo "$POT_DATA" | awk -F'\t' '{print $2}')
    P_STAGE=$(echo "$POT_DATA" | awk -F'\t' '{print $3}')
fi

# 5. Get current overall counts for anti-gaming (did they actually create new things?)
CURRENT_CONTACT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_contactdetails cd INNER JOIN vtiger_crmentity ce ON ce.crmid=cd.contactid WHERE ce.deleted=0" | tr -d '[:space:]')
CURRENT_ORG_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_account a INNER JOIN vtiger_crmentity ce ON ce.crmid=a.accountid WHERE ce.deleted=0" | tr -d '[:space:]')

# Create JSON Report
TEMP_JSON=$(mktemp /tmp/convert_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "lead_converted": "${LEAD_CONVERTED:-0}",
  "contact_count_match": ${CONTACT_COUNT:-0},
  "org_count_match": ${ORG_COUNT:-0},
  "pot_exists": ${POT_EXISTS},
  "pot_name": "$(json_escape "${P_NAME}")",
  "pot_amount": "$(json_escape "${P_AMOUNT}")",
  "pot_stage": "$(json_escape "${P_STAGE}")",
  "initial_counts": {
    "contacts": $INITIAL_CONTACT_COUNT,
    "orgs": $INITIAL_ORG_COUNT,
    "pots": $INITIAL_POT_COUNT
  },
  "current_counts": {
    "contacts": $CURRENT_CONTACT_COUNT,
    "orgs": $CURRENT_ORG_COUNT
  }
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="