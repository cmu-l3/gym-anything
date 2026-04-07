#!/bin/bash
set -e
echo "=== Exporting record_asset_addition results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_ADDITION_COUNT=$(cat /tmp/initial_addition_count.txt 2>/dev/null || echo "0")

# -----------------------------------------------------------------------------
# 1. Capture Final State
# -----------------------------------------------------------------------------
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------------
# 2. Query Database for Results
# -----------------------------------------------------------------------------
CLIENT_ID=$(get_gardenworld_client_id)

# Retrieve the Asset ID again
ASSET_ID=$(idempiere_query "SELECT a_asset_id FROM a_asset WHERE value='VAN-001' AND ad_client_id=$CLIENT_ID" 2>/dev/null)

if [ -z "$ASSET_ID" ]; then
    echo "Error: Asset VAN-001 not found during export."
    ASSET_ID="0"
fi

# Check for new additions created AFTER task start
# We look for the MOST RECENT addition to this asset
# Fields: AssetValueAmt, Description, Created
RAW_RESULT=$(idempiere_query "
    SELECT assetvalueamt, description, created 
    FROM a_asset_addition 
    WHERE a_asset_id=$ASSET_ID 
    ORDER BY a_asset_addition_id DESC 
    LIMIT 1
" 2>/dev/null)

# Parse the result (psql output can be pipe or nothing)
# Format expectation: 2500.00|Hydraulic Lift Gate Installation|2025-03-07 10:00:00
AMOUNT=""
DESCRIPTION=""
CREATED_DATE=""
RECORD_FOUND="false"

if [ -n "$RAW_RESULT" ]; then
    RECORD_FOUND="true"
    AMOUNT=$(echo "$RAW_RESULT" | cut -d'|' -f1)
    DESCRIPTION=$(echo "$RAW_RESULT" | cut -d'|' -f2)
    CREATED_DATE=$(echo "$RAW_RESULT" | cut -d'|' -f3)
fi

# Get current count
CURRENT_ADDITION_COUNT=$(idempiere_query "SELECT COUNT(*) FROM a_asset_addition WHERE a_asset_id=$ASSET_ID" 2>/dev/null || echo "0")

# Check if app was running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# -----------------------------------------------------------------------------
# 3. Create JSON Result
# -----------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_count": $INITIAL_ADDITION_COUNT,
    "current_count": $CURRENT_ADDITION_COUNT,
    "record_found": $RECORD_FOUND,
    "asset_id": "$ASSET_ID",
    "amount": "$AMOUNT",
    "description": "$DESCRIPTION",
    "created_date": "$CREATED_DATE",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="