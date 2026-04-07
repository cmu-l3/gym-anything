#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Read Setup Data
if [ -f /tmp/initial_bp_state.json ]; then
    BP_ID=$(jq -r '.bp_id' /tmp/initial_bp_state.json)
    INITIAL_UPDATED_TS=$(jq -r '.initial_updated_ts' /tmp/initial_bp_state.json)
    TASK_START_TS=$(jq -r '.task_start_ts' /tmp/initial_bp_state.json)
else
    # Fallback/Fail safe
    echo "WARNING: Initial state file missing"
    BP_ID=$(idempiere_query "SELECT c_bpartner_id FROM c_bpartner WHERE name='Seed Farm Inc.' AND ad_client_id=11 LIMIT 1")
    INITIAL_UPDATED_TS=0
    TASK_START_TS=0
fi

echo "Checking BP ID: $BP_ID"

# 3. Query Final Database State
# We need: SO Credit Limit, SO Credit Status, Payment Rule, and Last Updated Timestamp
# Note: paymentrule might be on c_bpartner or c_bp_customer depending on config, usually c_bpartner in default
DB_RESULT=$(idempiere_query "SELECT so_creditlimit, socreditstatus, paymentrule, extract(epoch from updated)::bigint FROM c_bpartner WHERE c_bpartner_id=$BP_ID")

# Parse result (psql output is pipe separated by default in some configs, or we used -A -t in utils)
# task_utils.sh uses: psql -t -A -c ... which implies pipe separator for multiple columns
CREDIT_LIMIT=$(echo "$DB_RESULT" | cut -d'|' -f1)
CREDIT_STATUS=$(echo "$DB_RESULT" | cut -d'|' -f2)
PAYMENT_RULE=$(echo "$DB_RESULT" | cut -d'|' -f3)
FINAL_UPDATED_TS=$(echo "$DB_RESULT" | cut -d'|' -f4)

# Handle nulls
CREDIT_LIMIT=${CREDIT_LIMIT:-0}
CREDIT_STATUS=${CREDIT_STATUS:-""}
PAYMENT_RULE=${PAYMENT_RULE:-""}
FINAL_UPDATED_TS=${FINAL_UPDATED_TS:-0}

# 4. Check modification time (Anti-Gaming)
MODIFIED_DURING_TASK="false"
if [ "$FINAL_UPDATED_TS" -gt "$TASK_START_TS" ]; then
    MODIFIED_DURING_TASK="true"
fi

# 5. Create JSON Result
# Using a temp file to avoid permission issues, then copying to /tmp/task_result.json
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "bp_id": "$BP_ID",
    "initial_ts": $INITIAL_UPDATED_TS,
    "final_ts": $FINAL_UPDATED_TS,
    "task_start_ts": $TASK_START_TS,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "final_values": {
        "so_credit_limit": $CREDIT_LIMIT,
        "so_credit_status": "$CREDIT_STATUS",
        "payment_rule": "$PAYMENT_RULE"
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="