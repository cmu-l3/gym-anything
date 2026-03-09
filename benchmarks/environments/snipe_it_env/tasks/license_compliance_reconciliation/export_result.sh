#!/bin/bash
echo "=== Exporting license_compliance_reconciliation results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/license_final.png

# Read baseline
MS365_ID=$(cat /tmp/license_ms365_id.txt 2>/dev/null || echo "0")
ADOBE_ID=$(cat /tmp/license_adobe_id.txt 2>/dev/null || echo "0")
WIN11_ID=$(cat /tmp/license_win11_id.txt 2>/dev/null || echo "0")
INITIAL_MS365_SEATS=$(cat /tmp/license_ms365_seats.txt 2>/dev/null || echo "0")
INITIAL_ADOBE_SEATS=$(cat /tmp/license_adobe_seats.txt 2>/dev/null || echo "0")
INITIAL_WIN11_EXPIRY=$(cat /tmp/license_win11_expiry.txt 2>/dev/null || echo "")
INITIAL_WIN11_ORDER=$(cat /tmp/license_win11_order.txt 2>/dev/null || echo "")
INITIAL_TOTAL=$(cat /tmp/license_total_count.txt 2>/dev/null || echo "0")

# ---------------------------------------------------------------
# Get current state of each license
# ---------------------------------------------------------------

# MS365
MS365_CURRENT=$(snipeit_db_query "SELECT seats, purchase_cost FROM licenses WHERE id=$MS365_ID AND deleted_at IS NULL LIMIT 1")
MS365_CUR_SEATS=$(echo "$MS365_CURRENT" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
MS365_CUR_COST=$(echo "$MS365_CURRENT" | awk -F'\t' '{print $2}' | tr -d '[:space:]')

# Adobe CC
ADOBE_CURRENT=$(snipeit_db_query "SELECT seats, purchase_cost FROM licenses WHERE id=$ADOBE_ID AND deleted_at IS NULL LIMIT 1")
ADOBE_CUR_SEATS=$(echo "$ADOBE_CURRENT" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
ADOBE_CUR_COST=$(echo "$ADOBE_CURRENT" | awk -F'\t' '{print $2}' | tr -d '[:space:]')

# Win11
WIN11_CURRENT=$(snipeit_db_query "SELECT expiration_date, order_number FROM licenses WHERE id=$WIN11_ID AND deleted_at IS NULL LIMIT 1")
WIN11_CUR_EXPIRY=$(echo "$WIN11_CURRENT" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
WIN11_CUR_ORDER=$(echo "$WIN11_CURRENT" | awk -F'\t' '{print $2}' | tr -d '[:space:]')

# New Slack license
SLACK_DATA=$(snipeit_db_query "SELECT id, name, serial, seats, purchase_cost, expiration_date, order_number, notes FROM licenses WHERE name LIKE '%Slack%' AND deleted_at IS NULL LIMIT 1")
SLACK_FOUND="false"
SLACK_NAME=""
SLACK_SERIAL=""
SLACK_SEATS=""
SLACK_COST=""
SLACK_EXPIRY=""
SLACK_ORDER=""
SLACK_NOTES=""
if [ -n "$SLACK_DATA" ]; then
    SLACK_FOUND="true"
    SLACK_NAME=$(echo "$SLACK_DATA" | awk -F'\t' '{print $2}')
    SLACK_SERIAL=$(echo "$SLACK_DATA" | awk -F'\t' '{print $3}')
    SLACK_SEATS=$(echo "$SLACK_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    SLACK_COST=$(echo "$SLACK_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
    SLACK_EXPIRY=$(echo "$SLACK_DATA" | awk -F'\t' '{print $6}' | tr -d '[:space:]')
    SLACK_ORDER=$(echo "$SLACK_DATA" | awk -F'\t' '{print $7}')
    SLACK_NOTES=$(echo "$SLACK_DATA" | awk -F'\t' '{print $8}')
fi

# Total license count now
CURRENT_TOTAL=$(snipeit_db_query "SELECT COUNT(*) FROM licenses WHERE deleted_at IS NULL" | tr -d '[:space:]')

# Build result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "ms365": {
    "id": $MS365_ID,
    "initial_seats": $INITIAL_MS365_SEATS,
    "current_seats": ${MS365_CUR_SEATS:-0},
    "current_cost": ${MS365_CUR_COST:-0}
  },
  "adobe_cc": {
    "id": $ADOBE_ID,
    "initial_seats": $INITIAL_ADOBE_SEATS,
    "current_seats": ${ADOBE_CUR_SEATS:-0},
    "current_cost": ${ADOBE_CUR_COST:-0}
  },
  "win11": {
    "id": $WIN11_ID,
    "initial_expiry": "$(json_escape "$INITIAL_WIN11_EXPIRY")",
    "current_expiry": "$(json_escape "$WIN11_CUR_EXPIRY")",
    "initial_order": "$(json_escape "$INITIAL_WIN11_ORDER")",
    "current_order": "$(json_escape "$WIN11_CUR_ORDER")"
  },
  "slack": {
    "found": $SLACK_FOUND,
    "name": "$(json_escape "$SLACK_NAME")",
    "serial": "$(json_escape "$SLACK_SERIAL")",
    "seats": "${SLACK_SEATS}",
    "cost": "${SLACK_COST}",
    "expiry": "$(json_escape "$SLACK_EXPIRY")",
    "order": "$(json_escape "$SLACK_ORDER")",
    "notes": "$(json_escape "$SLACK_NOTES")"
  },
  "initial_total_licenses": $INITIAL_TOTAL,
  "current_total_licenses": $CURRENT_TOTAL
}
JSONEOF
)

safe_write_result "/tmp/license_compliance_reconciliation_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/license_compliance_reconciliation_result.json"
echo "$RESULT_JSON"
echo "=== license_compliance_reconciliation export complete ==="
