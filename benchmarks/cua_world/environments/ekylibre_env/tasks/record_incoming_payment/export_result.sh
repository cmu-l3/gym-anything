#!/bin/bash
set -e
echo "=== Exporting record_incoming_payment results ==="

source /workspace/scripts/task_utils.sh

TENANT="demo"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_incoming_payments_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# ============================================================
# 1. Query Database for Result
# ============================================================
echo "Querying database for payment record..."

# We look for a payment matching the criteria created after task start
# Criteria: Amount ~ 8750, Payer ~ Coopérative Agricole de Charente
QUERY="
SET search_path TO ${TENANT}, postgis, lexicon, public;
SELECT 
    ip.id, 
    ip.amount, 
    ip.paid_at, 
    ip.bank_check_number, 
    e.full_name,
    EXTRACT(EPOCH FROM ip.created_at) as created_ts
FROM incoming_payments ip
LEFT JOIN entities e ON ip.payer_id = e.id
WHERE ip.amount BETWEEN 8749.0 AND 8751.0
  AND e.full_name LIKE '%Coop%rative%Charente%'
ORDER BY ip.created_at DESC
LIMIT 1;
"

PAYMENT_DATA=$(ekylibre_db_query "$QUERY" 2>/dev/null || echo "")

# Parse the result (pipe-delimited by default in some configs, or standard psql output)
# We use a safer approach: specific query for each field if needed, or parse strictly
# Let's assume standard psql output: id|amount|paid_at|check_num|payer_name|created_ts

PAYMENT_FOUND="false"
PAYMENT_ID=""
PAYMENT_AMOUNT=""
PAYMENT_DATE=""
PAYMENT_REF=""
PAYMENT_PAYER=""
PAYMENT_CREATED_TS="0"

if [ -n "$PAYMENT_DATA" ]; then
    PAYMENT_FOUND="true"
    PAYMENT_ID=$(echo "$PAYMENT_DATA" | cut -d'|' -f1)
    PAYMENT_AMOUNT=$(echo "$PAYMENT_DATA" | cut -d'|' -f2)
    PAYMENT_DATE=$(echo "$PAYMENT_DATA" | cut -d'|' -f3)
    PAYMENT_REF=$(echo "$PAYMENT_DATA" | cut -d'|' -f4)
    PAYMENT_PAYER=$(echo "$PAYMENT_DATA" | cut -d'|' -f5)
    PAYMENT_CREATED_TS=$(echo "$PAYMENT_DATA" | cut -d'|' -f6 | cut -d'.' -f1) # Integer timestamp
fi

# Get current count
CURRENT_COUNT=$(ekylibre_db_query "SET search_path TO ${TENANT}, postgis, lexicon, public; SELECT count(*) FROM incoming_payments;" 2>/dev/null || echo "0")

# Check if app was running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# ============================================================
# 2. Create JSON Result
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "payment_found": $PAYMENT_FOUND,
    "payment_details": {
        "id": "$PAYMENT_ID",
        "amount": "$PAYMENT_AMOUNT",
        "date": "$PAYMENT_DATE",
        "reference": "$PAYMENT_REF",
        "payer": "$PAYMENT_PAYER",
        "created_timestamp": $PAYMENT_CREATED_TS
    },
    "counts": {
        "initial": $INITIAL_COUNT,
        "final": $CURRENT_COUNT
    },
    "task_start_timestamp": $TASK_START,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="