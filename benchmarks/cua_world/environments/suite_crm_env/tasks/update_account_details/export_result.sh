#!/bin/bash
echo "=== Exporting update_account_details result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ACCOUNT_ID=$(cat /tmp/target_account_id.txt 2>/dev/null || echo "")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Retrieve current duplicate count
MERIDIAN_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM accounts WHERE name='Meridian Technologies Inc' AND deleted=0" | tr -d '[:space:]')
INITIAL_COUNT=$(cat /tmp/initial_account_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_account_count)

# Query fields individually to avoid delimiter collision issues in bash
if [ -n "$ACCOUNT_ID" ]; then
    A_EXISTS=$(suitecrm_db_query "SELECT COUNT(*) FROM accounts WHERE id='${ACCOUNT_ID}' AND deleted=0" | tr -d '[:space:]')
    
    A_STREET=$(suitecrm_db_query "SELECT billing_address_street FROM accounts WHERE id='${ACCOUNT_ID}'")
    A_CITY=$(suitecrm_db_query "SELECT billing_address_city FROM accounts WHERE id='${ACCOUNT_ID}'")
    A_STATE=$(suitecrm_db_query "SELECT billing_address_state FROM accounts WHERE id='${ACCOUNT_ID}'")
    A_ZIP=$(suitecrm_db_query "SELECT billing_address_postalcode FROM accounts WHERE id='${ACCOUNT_ID}'")
    A_PHONE=$(suitecrm_db_query "SELECT phone_office FROM accounts WHERE id='${ACCOUNT_ID}'")
    A_INDUSTRY=$(suitecrm_db_query "SELECT industry FROM accounts WHERE id='${ACCOUNT_ID}'")
    A_DESC=$(suitecrm_db_query "SELECT description FROM accounts WHERE id='${ACCOUNT_ID}'")
    
    # Check if modified_date is different from date_entered to prove modification
    A_MODIFIED=$(suitecrm_db_query "SELECT CASE WHEN date_modified > date_entered THEN 1 ELSE 0 END FROM accounts WHERE id='${ACCOUNT_ID}'" | tr -d '[:space:]')
else
    A_EXISTS="0"
    A_STREET=""
    A_CITY=""
    A_STATE=""
    A_ZIP=""
    A_PHONE=""
    A_INDUSTRY=""
    A_DESC=""
    A_MODIFIED="0"
fi

# Build JSON using helper
RESULT_JSON=$(cat << JSONEOF
{
  "task_start": ${TASK_START},
  "account_id": "$(json_escape "${ACCOUNT_ID:-}")",
  "account_exists": ${A_EXISTS:-0},
  "is_modified": ${A_MODIFIED:-0},
  "meridian_count": ${MERIDIAN_COUNT:-0},
  "initial_total_count": ${INITIAL_COUNT:-0},
  "current_total_count": ${CURRENT_COUNT:-0},
  "billing_street": "$(json_escape "${A_STREET:-}")",
  "billing_city": "$(json_escape "${A_CITY:-}")",
  "billing_state": "$(json_escape "${A_STATE:-}")",
  "billing_zip": "$(json_escape "${A_ZIP:-}")",
  "phone": "$(json_escape "${A_PHONE:-}")",
  "industry": "$(json_escape "${A_INDUSTRY:-}")",
  "description": "$(json_escape "${A_DESC:-}")"
}
JSONEOF
)

# Write result securely
safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="