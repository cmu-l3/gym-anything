#!/bin/bash
echo "=== Exporting renew_service_contract results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/renew_contract_final.png

INITIAL_CONTRACT_COUNT=$(cat /tmp/initial_contract_count.txt 2>/dev/null || echo "0")
CURRENT_CONTRACT_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aos_contracts WHERE deleted=0" | tr -d '[:space:]')

# Query the OLD contract to make sure it's intact
OLD_CONTRACT_DATA=$(suitecrm_db_query "SELECT id, name, status, total_contract_value FROM aos_contracts WHERE name='Vanguard Data Systems - Enterprise SLA 2024' AND deleted=0 LIMIT 1")

OLD_FOUND="false"
OLD_ID=""
OLD_NAME=""
OLD_STATUS=""
OLD_VALUE=""

if [ -n "$OLD_CONTRACT_DATA" ]; then
    OLD_FOUND="true"
    OLD_ID=$(echo "$OLD_CONTRACT_DATA" | awk -F'\t' '{print $1}')
    OLD_NAME=$(echo "$OLD_CONTRACT_DATA" | awk -F'\t' '{print $2}')
    OLD_STATUS=$(echo "$OLD_CONTRACT_DATA" | awk -F'\t' '{print $3}')
    OLD_VALUE=$(echo "$OLD_CONTRACT_DATA" | awk -F'\t' '{print $4}')
fi

# Query the NEW contract (check both AOS_Contracts and legacy Contracts tables)
NEW_CONTRACT_DATA=$(suitecrm_db_query "SELECT c.id, c.name, c.status, c.start_date, c.end_date, c.customer_signed_date, c.total_contract_value, a.name as account_name FROM aos_contracts c LEFT JOIN accounts a ON c.contract_account_id = a.id WHERE c.name='Vanguard Data Systems - Enterprise SLA 2025' AND c.deleted=0 LIMIT 1")

# If not found in AOS_Contracts, check legacy Contracts table
if [ -z "$NEW_CONTRACT_DATA" ]; then
    NEW_CONTRACT_DATA=$(suitecrm_db_query "SELECT c.id, c.name, c.status, c.start_date, c.end_date, c.customer_signed_date, c.total_contract_value, a.name as account_name FROM contracts c LEFT JOIN accounts a ON c.account_id = a.id WHERE c.name='Vanguard Data Systems - Enterprise SLA 2025' AND c.deleted=0 LIMIT 1")
fi

NEW_FOUND="false"
NEW_ID=""
NEW_NAME=""
NEW_STATUS=""
NEW_START=""
NEW_END=""
NEW_SIGNED=""
NEW_VALUE=""
NEW_ACCOUNT=""

if [ -n "$NEW_CONTRACT_DATA" ]; then
    NEW_FOUND="true"
    NEW_ID=$(echo "$NEW_CONTRACT_DATA" | awk -F'\t' '{print $1}')
    NEW_NAME=$(echo "$NEW_CONTRACT_DATA" | awk -F'\t' '{print $2}')
    NEW_STATUS=$(echo "$NEW_CONTRACT_DATA" | awk -F'\t' '{print $3}')
    NEW_START=$(echo "$NEW_CONTRACT_DATA" | awk -F'\t' '{print $4}')
    NEW_END=$(echo "$NEW_CONTRACT_DATA" | awk -F'\t' '{print $5}')
    NEW_SIGNED=$(echo "$NEW_CONTRACT_DATA" | awk -F'\t' '{print $6}')
    NEW_VALUE=$(echo "$NEW_CONTRACT_DATA" | awk -F'\t' '{print $7}')
    NEW_ACCOUNT=$(echo "$NEW_CONTRACT_DATA" | awk -F'\t' '{print $8}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "old_contract": {
    "found": ${OLD_FOUND},
    "id": "$(json_escape "${OLD_ID}")",
    "name": "$(json_escape "${OLD_NAME}")",
    "status": "$(json_escape "${OLD_STATUS}")",
    "total_value": "$(json_escape "${OLD_VALUE}")"
  },
  "new_contract": {
    "found": ${NEW_FOUND},
    "id": "$(json_escape "${NEW_ID}")",
    "name": "$(json_escape "${NEW_NAME}")",
    "status": "$(json_escape "${NEW_STATUS}")",
    "start_date": "$(json_escape "${NEW_START}")",
    "end_date": "$(json_escape "${NEW_END}")",
    "signed_date": "$(json_escape "${NEW_SIGNED}")",
    "total_value": "$(json_escape "${NEW_VALUE}")",
    "account_name": "$(json_escape "${NEW_ACCOUNT}")"
  },
  "initial_count": ${INITIAL_CONTRACT_COUNT:-0},
  "current_count": ${CURRENT_CONTRACT_COUNT:-0}
}
JSONEOF
)

safe_write_result "/tmp/renew_contract_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/renew_contract_result.json"
cat /tmp/renew_contract_result.json
echo "=== renew_service_contract export complete ==="