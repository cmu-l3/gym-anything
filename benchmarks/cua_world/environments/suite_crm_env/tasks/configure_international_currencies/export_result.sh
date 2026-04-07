#!/bin/bash
echo "=== Exporting configure_international_currencies results ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/configure_currencies_final.png

# Retrieve EUR Data
EUR_DATA=$(suitecrm_db_query "SELECT id, name, symbol, iso4217, conversion_rate, status FROM currencies WHERE iso4217='EUR' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

# Retrieve GBP Data
GBP_DATA=$(suitecrm_db_query "SELECT id, name, symbol, iso4217, conversion_rate, status FROM currencies WHERE iso4217='GBP' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

# Retrieve Base Currency Rate (usually id='-99')
BASE_DATA=$(suitecrm_db_query "SELECT conversion_rate FROM currencies WHERE id='-99' AND deleted=0")

# Parse EUR
EUR_FOUND="false"
if [ -n "$EUR_DATA" ]; then
    EUR_FOUND="true"
    EUR_NAME=$(echo "$EUR_DATA" | awk -F'\t' '{print $2}')
    EUR_SYMBOL=$(echo "$EUR_DATA" | awk -F'\t' '{print $3}')
    EUR_RATE=$(echo "$EUR_DATA" | awk -F'\t' '{print $5}')
    EUR_STATUS=$(echo "$EUR_DATA" | awk -F'\t' '{print $6}')
fi

# Parse GBP
GBP_FOUND="false"
if [ -n "$GBP_DATA" ]; then
    GBP_FOUND="true"
    GBP_NAME=$(echo "$GBP_DATA" | awk -F'\t' '{print $2}')
    GBP_SYMBOL=$(echo "$GBP_DATA" | awk -F'\t' '{print $3}')
    GBP_RATE=$(echo "$GBP_DATA" | awk -F'\t' '{print $5}')
    GBP_STATUS=$(echo "$GBP_DATA" | awk -F'\t' '{print $6}')
fi

# Construct Result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "eur_found": ${EUR_FOUND},
  "eur_name": "$(json_escape "${EUR_NAME:-}")",
  "eur_symbol": "$(json_escape "${EUR_SYMBOL:-}")",
  "eur_rate": "$(json_escape "${EUR_RATE:-}")",
  "eur_status": "$(json_escape "${EUR_STATUS:-}")",
  "gbp_found": ${GBP_FOUND},
  "gbp_name": "$(json_escape "${GBP_NAME:-}")",
  "gbp_symbol": "$(json_escape "${GBP_SYMBOL:-}")",
  "gbp_rate": "$(json_escape "${GBP_RATE:-}")",
  "gbp_status": "$(json_escape "${GBP_STATUS:-}")",
  "base_rate": "$(json_escape "${BASE_DATA:-1.0}")"
}
JSONEOF
)

safe_write_result "/tmp/currencies_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/currencies_result.json"
echo "$RESULT_JSON"
echo "=== configure_international_currencies export complete ==="