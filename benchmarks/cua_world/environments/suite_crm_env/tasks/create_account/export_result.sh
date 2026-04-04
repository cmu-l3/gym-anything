#!/bin/bash
echo "=== Exporting create_account results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/create_account_final.png

INITIAL_ACCOUNT_COUNT=$(cat /tmp/initial_account_count.txt 2>/dev/null || echo "0")
CURRENT_ACCOUNT_COUNT=$(get_account_count)

ACCOUNT_DATA=$(suitecrm_db_query "SELECT id, name, industry, account_type, phone_office, website, billing_address_street, billing_address_city, billing_address_state, billing_address_postalcode, billing_address_country, employees, annual_revenue FROM accounts WHERE name='Redwood Consulting Partners' AND deleted=0 LIMIT 1")

ACCOUNT_FOUND="false"
if [ -n "$ACCOUNT_DATA" ]; then
    ACCOUNT_FOUND="true"
    A_ID=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $1}')
    A_NAME=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $2}')
    A_INDUSTRY=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $3}')
    A_TYPE=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $4}')
    A_PHONE=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $5}')
    A_WEBSITE=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $6}')
    A_STREET=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $7}')
    A_CITY=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $8}')
    A_STATE=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $9}')
    A_ZIP=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $10}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "account_found": ${ACCOUNT_FOUND},
  "account_id": "$(json_escape "${A_ID:-}")",
  "name": "$(json_escape "${A_NAME:-}")",
  "industry": "$(json_escape "${A_INDUSTRY:-}")",
  "account_type": "$(json_escape "${A_TYPE:-}")",
  "phone": "$(json_escape "${A_PHONE:-}")",
  "website": "$(json_escape "${A_WEBSITE:-}")",
  "billing_street": "$(json_escape "${A_STREET:-}")",
  "billing_city": "$(json_escape "${A_CITY:-}")",
  "billing_state": "$(json_escape "${A_STATE:-}")",
  "initial_count": ${INITIAL_ACCOUNT_COUNT},
  "current_count": ${CURRENT_ACCOUNT_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/create_account_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_account_result.json"
echo "$RESULT_JSON"
echo "=== create_account export complete ==="
