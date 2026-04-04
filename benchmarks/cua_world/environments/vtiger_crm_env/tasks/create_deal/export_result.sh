#!/bin/bash
echo "=== Exporting create_deal results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/create_deal_final.png

INITIAL_DEAL_COUNT=$(cat /tmp/initial_deal_count.txt 2>/dev/null || echo "0")
CURRENT_DEAL_COUNT=$(get_deal_count)

DEAL_DATA=$(vtiger_db_query "SELECT p.potentialid, p.potentialname, p.amount, p.closingdate, p.sales_stage, p.probability FROM vtiger_potential p WHERE p.potentialname='DataForge Enterprise Analytics Rollout' LIMIT 1")

DEAL_FOUND="false"
if [ -n "$DEAL_DATA" ]; then
    DEAL_FOUND="true"
    D_ID=$(echo "$DEAL_DATA" | awk -F'\t' '{print $1}')
    D_NAME=$(echo "$DEAL_DATA" | awk -F'\t' '{print $2}')
    D_AMOUNT=$(echo "$DEAL_DATA" | awk -F'\t' '{print $3}')
    D_CLOSE=$(echo "$DEAL_DATA" | awk -F'\t' '{print $4}')
    D_STAGE=$(echo "$DEAL_DATA" | awk -F'\t' '{print $5}')
    D_PROB=$(echo "$DEAL_DATA" | awk -F'\t' '{print $6}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "deal_found": ${DEAL_FOUND},
  "deal_id": "$(json_escape "${D_ID:-}")",
  "name": "$(json_escape "${D_NAME:-}")",
  "amount": "$(json_escape "${D_AMOUNT:-}")",
  "closing_date": "$(json_escape "${D_CLOSE:-}")",
  "sales_stage": "$(json_escape "${D_STAGE:-}")",
  "probability": "$(json_escape "${D_PROB:-}")",
  "initial_count": ${INITIAL_DEAL_COUNT},
  "current_count": ${CURRENT_DEAL_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/create_deal_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_deal_result.json"
echo "$RESULT_JSON"
echo "=== create_deal export complete ==="
