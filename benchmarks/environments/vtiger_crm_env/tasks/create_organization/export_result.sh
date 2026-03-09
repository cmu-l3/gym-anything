#!/bin/bash
echo "=== Exporting create_organization results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/create_organization_final.png

INITIAL_ORG_COUNT=$(cat /tmp/initial_org_count.txt 2>/dev/null || echo "0")
CURRENT_ORG_COUNT=$(get_org_count)

ORG_DATA=$(vtiger_db_query "SELECT a.accountid, a.accountname, a.phone, a.website, a.industry, a.annual_revenue, a.employees, b.bill_street, b.bill_city, b.bill_state, b.bill_code, b.bill_country FROM vtiger_account a LEFT JOIN vtiger_accountbillads b ON a.accountid=b.accountaddressid WHERE a.accountname='Redwood Consulting Partners' LIMIT 1")

ORG_FOUND="false"
if [ -n "$ORG_DATA" ]; then
    ORG_FOUND="true"
    O_ID=$(echo "$ORG_DATA" | awk -F'\t' '{print $1}')
    O_NAME=$(echo "$ORG_DATA" | awk -F'\t' '{print $2}')
    O_PHONE=$(echo "$ORG_DATA" | awk -F'\t' '{print $3}')
    O_WEBSITE=$(echo "$ORG_DATA" | awk -F'\t' '{print $4}')
    O_INDUSTRY=$(echo "$ORG_DATA" | awk -F'\t' '{print $5}')
    O_REVENUE=$(echo "$ORG_DATA" | awk -F'\t' '{print $6}')
    O_EMPLOYEES=$(echo "$ORG_DATA" | awk -F'\t' '{print $7}')
    O_STREET=$(echo "$ORG_DATA" | awk -F'\t' '{print $8}')
    O_CITY=$(echo "$ORG_DATA" | awk -F'\t' '{print $9}')
    O_STATE=$(echo "$ORG_DATA" | awk -F'\t' '{print $10}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "org_found": ${ORG_FOUND},
  "org_id": "$(json_escape "${O_ID:-}")",
  "name": "$(json_escape "${O_NAME:-}")",
  "phone": "$(json_escape "${O_PHONE:-}")",
  "website": "$(json_escape "${O_WEBSITE:-}")",
  "industry": "$(json_escape "${O_INDUSTRY:-}")",
  "annual_revenue": "$(json_escape "${O_REVENUE:-}")",
  "employees": "$(json_escape "${O_EMPLOYEES:-}")",
  "billing_street": "$(json_escape "${O_STREET:-}")",
  "billing_city": "$(json_escape "${O_CITY:-}")",
  "billing_state": "$(json_escape "${O_STATE:-}")",
  "initial_count": ${INITIAL_ORG_COUNT},
  "current_count": ${CURRENT_ORG_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/create_organization_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_organization_result.json"
echo "$RESULT_JSON"
echo "=== create_organization export complete ==="
