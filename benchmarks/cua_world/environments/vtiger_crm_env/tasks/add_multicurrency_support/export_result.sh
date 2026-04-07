#!/bin/bash
echo "=== Exporting add_multicurrency_support results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/add_multicurrency_final.png

# Read initial state
INITIAL_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_currency_state.json')).get('initial_count', 0))" 2>/dev/null || echo "0")
MAX_INITIAL_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_currency_state.json')).get('max_initial_id', 0))" 2>/dev/null || echo "0")

# Get current currency count
CURRENT_COUNT=$(vtiger_count "vtiger_currency_info" "deleted=0")

# Query EUR data
EUR_DATA=$(vtiger_db_query "SELECT id, conversion_rate, currency_status FROM vtiger_currency_info WHERE currency_code='EUR' AND deleted=0 ORDER BY id DESC LIMIT 1")
EUR_FOUND="false"
if [ -n "$EUR_DATA" ]; then
    EUR_FOUND="true"
    EUR_ID=$(echo "$EUR_DATA" | awk -F'\t' '{print $1}')
    EUR_RATE=$(echo "$EUR_DATA" | awk -F'\t' '{print $2}')
    EUR_STATUS=$(echo "$EUR_DATA" | awk -F'\t' '{print $3}')
fi

# Query GBP data
GBP_DATA=$(vtiger_db_query "SELECT id, conversion_rate, currency_status FROM vtiger_currency_info WHERE currency_code='GBP' AND deleted=0 ORDER BY id DESC LIMIT 1")
GBP_FOUND="false"
if [ -n "$GBP_DATA" ]; then
    GBP_FOUND="true"
    GBP_ID=$(echo "$GBP_DATA" | awk -F'\t' '{print $1}')
    GBP_RATE=$(echo "$GBP_DATA" | awk -F'\t' '{print $2}')
    GBP_STATUS=$(echo "$GBP_DATA" | awk -F'\t' '{print $3}')
fi

# Prepare JSON
RESULT_JSON=$(cat << JSONEOF
{
  "initial_count": ${INITIAL_COUNT},
  "current_count": ${CURRENT_COUNT},
  "max_initial_id": ${MAX_INITIAL_ID},
  "eur": {
    "found": ${EUR_FOUND},
    "id": ${EUR_ID:-0},
    "rate": "${EUR_RATE:-0}",
    "status": "$(json_escape "${EUR_STATUS:-}")"
  },
  "gbp": {
    "found": ${GBP_FOUND},
    "id": ${GBP_ID:-0},
    "rate": "${GBP_RATE:-0}",
    "status": "$(json_escape "${GBP_STATUS:-}")"
  }
}
JSONEOF
)

safe_write_result "/tmp/add_multicurrency_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/add_multicurrency_result.json"
echo "$RESULT_JSON"
echo "=== add_multicurrency_support export complete ==="