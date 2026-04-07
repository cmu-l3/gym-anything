#!/bin/bash
echo "=== Exporting add_custom_dropdown_values results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/add_custom_dropdown_values_final.png

# Retrieve baseline state
INITIAL_ACCOUNT_COUNT=$(cat /tmp/initial_account_count.txt 2>/dev/null || echo "0")
CURRENT_ACCOUNT_COUNT=$(get_account_count)

HAS_INITIAL_RENEWABLE=$(cat /tmp/has_initial_renewable.txt 2>/dev/null || echo "false")
HAS_INITIAL_WEBINAR=$(cat /tmp/has_initial_webinar.txt 2>/dev/null || echo "false")

# 1. Check if Dropdown files were modified by grepping the custom language directory in the container
HAS_RENEWABLE=$(docker exec suitecrm-app grep -qri "Renewable_Energy" /var/www/html/custom/ 2>/dev/null && echo "true" || echo "false")
HAS_WEBINAR=$(docker exec suitecrm-app grep -qri "Webinar" /var/www/html/custom/ 2>/dev/null && echo "true" || echo "false")

# 2. Check if the Account was created with the correct industry key
ACCOUNT_DATA=$(suitecrm_db_query "SELECT id, name, industry, date_entered FROM accounts WHERE name='SolarTech Solutions' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

ACCOUNT_FOUND="false"
if [ -n "$ACCOUNT_DATA" ]; then
    ACCOUNT_FOUND="true"
    A_ID=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $1}')
    A_NAME=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $2}')
    A_INDUSTRY=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $3}')
    A_DATE=$(echo "$ACCOUNT_DATA" | awk -F'\t' '{print $4}')
fi

# Write results to JSON
RESULT_JSON=$(cat << JSONEOF
{
  "account_found": ${ACCOUNT_FOUND},
  "account_id": "$(json_escape "${A_ID:-}")",
  "account_name": "$(json_escape "${A_NAME:-}")",
  "account_industry": "$(json_escape "${A_INDUSTRY:-}")",
  "account_date_entered": "$(json_escape "${A_DATE:-}")",
  "initial_count": ${INITIAL_ACCOUNT_COUNT},
  "current_count": ${CURRENT_ACCOUNT_COUNT},
  "baseline_has_renewable": ${HAS_INITIAL_RENEWABLE},
  "baseline_has_webinar": ${HAS_INITIAL_WEBINAR},
  "final_has_renewable": ${HAS_RENEWABLE},
  "final_has_webinar": ${HAS_WEBINAR}
}
JSONEOF
)

safe_write_result "/tmp/add_custom_dropdown_values_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/add_custom_dropdown_values_result.json"
cat /tmp/add_custom_dropdown_values_result.json
echo "=== add_custom_dropdown_values export complete ==="