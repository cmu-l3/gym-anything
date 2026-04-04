#!/bin/bash
echo "=== Exporting create_opportunity results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/create_opportunity_final.png

INITIAL_OPP_COUNT=$(cat /tmp/initial_opp_count.txt 2>/dev/null || echo "0")
CURRENT_OPP_COUNT=$(get_opp_count)

OPP_DATA=$(suitecrm_db_query "SELECT id, name, amount, sales_stage, probability, date_closed, lead_source, opportunity_type, description FROM opportunities WHERE name='GE Aerospace - Predictive Maintenance Platform' AND deleted=0 LIMIT 1")

OPP_FOUND="false"
if [ -n "$OPP_DATA" ]; then
    OPP_FOUND="true"
    O_ID=$(echo "$OPP_DATA" | awk -F'\t' '{print $1}')
    O_NAME=$(echo "$OPP_DATA" | awk -F'\t' '{print $2}')
    O_AMOUNT=$(echo "$OPP_DATA" | awk -F'\t' '{print $3}')
    O_STAGE=$(echo "$OPP_DATA" | awk -F'\t' '{print $4}')
    O_PROB=$(echo "$OPP_DATA" | awk -F'\t' '{print $5}')
    O_CLOSE=$(echo "$OPP_DATA" | awk -F'\t' '{print $6}')
    O_SOURCE=$(echo "$OPP_DATA" | awk -F'\t' '{print $7}')
    O_TYPE=$(echo "$OPP_DATA" | awk -F'\t' '{print $8}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "opportunity_found": ${OPP_FOUND},
  "opportunity_id": "$(json_escape "${O_ID:-}")",
  "name": "$(json_escape "${O_NAME:-}")",
  "amount": "$(json_escape "${O_AMOUNT:-}")",
  "sales_stage": "$(json_escape "${O_STAGE:-}")",
  "probability": "$(json_escape "${O_PROB:-}")",
  "date_closed": "$(json_escape "${O_CLOSE:-}")",
  "lead_source": "$(json_escape "${O_SOURCE:-}")",
  "opportunity_type": "$(json_escape "${O_TYPE:-}")",
  "initial_count": ${INITIAL_OPP_COUNT},
  "current_count": ${CURRENT_OPP_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/create_opportunity_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_opportunity_result.json"
echo "$RESULT_JSON"
echo "=== create_opportunity export complete ==="
