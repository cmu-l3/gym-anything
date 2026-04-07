#!/bin/bash
echo "=== Exporting create_contract results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for trajectory and visual evidence
take_screenshot /tmp/create_contract_final.png

# Read baseline metrics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_CONTRACT_COUNT=$(cat /tmp/initial_contract_count.txt 2>/dev/null || echo "0")
CURRENT_CONTRACT_COUNT=$(suitecrm_count "aos_contracts" "deleted=0")

# Query the database for the created contract
# SuiteCRM Advanced OpenSales (AOS) uses aos_contracts table
CONTRACT_DATA=$(suitecrm_db_query "SELECT c.id, c.name, c.status, c.start_date, c.end_date, c.total_contract_value, c.description, c.contract_account_id, a.name AS account_name, UNIX_TIMESTAMP(c.date_entered) FROM aos_contracts c LEFT JOIN accounts a ON c.contract_account_id = a.id AND a.deleted = 0 WHERE c.name = 'Annual Maintenance Agreement 2024' AND c.deleted = 0 ORDER BY c.date_entered DESC LIMIT 1")

CONTRACT_FOUND="false"
if [ -n "$CONTRACT_DATA" ]; then
    CONTRACT_FOUND="true"
    C_ID=$(echo "$CONTRACT_DATA" | awk -F'\t' '{print $1}')
    C_NAME=$(echo "$CONTRACT_DATA" | awk -F'\t' '{print $2}')
    C_STATUS=$(echo "$CONTRACT_DATA" | awk -F'\t' '{print $3}')
    C_START=$(echo "$CONTRACT_DATA" | awk -F'\t' '{print $4}')
    C_END=$(echo "$CONTRACT_DATA" | awk -F'\t' '{print $5}')
    C_VAL=$(echo "$CONTRACT_DATA" | awk -F'\t' '{print $6}')
    C_DESC=$(echo "$CONTRACT_DATA" | awk -F'\t' '{print $7}')
    C_ACCT_ID=$(echo "$CONTRACT_DATA" | awk -F'\t' '{print $8}')
    C_ACCT_NAME=$(echo "$CONTRACT_DATA" | awk -F'\t' '{print $9}')
    C_TS=$(echo "$CONTRACT_DATA" | awk -F'\t' '{print $10}')
fi

# Generate JSON result file
RESULT_JSON=$(cat << JSONEOF
{
  "contract_found": ${CONTRACT_FOUND},
  "task_start_time": ${TASK_START},
  "contract_id": "$(json_escape "${C_ID:-}")",
  "name": "$(json_escape "${C_NAME:-}")",
  "status": "$(json_escape "${C_STATUS:-}")",
  "start_date": "$(json_escape "${C_START:-}")",
  "end_date": "$(json_escape "${C_END:-}")",
  "total_value": "$(json_escape "${C_VAL:-0}")",
  "description": "$(json_escape "${C_DESC:-}")",
  "account_id": "$(json_escape "${C_ACCT_ID:-}")",
  "account_name": "$(json_escape "${C_ACCT_NAME:-}")",
  "date_entered_ts": ${C_TS:-0},
  "initial_count": ${INITIAL_CONTRACT_COUNT},
  "current_count": ${CURRENT_CONTRACT_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/create_contract_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_contract_result.json"
echo "$RESULT_JSON"
echo "=== create_contract export complete ==="