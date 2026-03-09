#!/bin/bash
echo "=== Exporting checkout_asset results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/checkout_asset_final.png

# Read initial state
ASSET_ID=$(cat /tmp/checkout_asset_id.txt 2>/dev/null || echo "0")
INITIAL_ASSIGNED=$(cat /tmp/initial_assigned_to.txt 2>/dev/null || echo "0")
TARGET_USER_ID=$(cat /tmp/target_user_id.txt 2>/dev/null || echo "0")

# Get current asset state
CURRENT_DATA=$(snipeit_db_query "SELECT assigned_to, assigned_type, status_id FROM assets WHERE id=${ASSET_ID} AND deleted_at IS NULL")
CURRENT_ASSIGNED=$(echo "$CURRENT_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
CURRENT_ASSIGNED_TYPE=$(echo "$CURRENT_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
CURRENT_STATUS_ID=$(echo "$CURRENT_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')

# Check if asset is now checked out to the target user
IS_CHECKED_OUT="false"
CORRECT_USER="false"

if [ -n "$CURRENT_ASSIGNED" ] && [ "$CURRENT_ASSIGNED" != "NULL" ] && [ "$CURRENT_ASSIGNED" != "0" ]; then
    IS_CHECKED_OUT="true"
    if [ "$CURRENT_ASSIGNED" = "$TARGET_USER_ID" ]; then
        CORRECT_USER="true"
    fi
fi

# Get the user it's checked out to (if any)
CHECKED_OUT_USER=""
CHECKED_OUT_USERNAME=""
if [ "$IS_CHECKED_OUT" = "true" ]; then
    CHECKED_OUT_USER=$(snipeit_db_query "SELECT CONCAT(first_name, ' ', last_name) FROM users WHERE id=${CURRENT_ASSIGNED}" | tr -d '\n')
    CHECKED_OUT_USERNAME=$(snipeit_db_query "SELECT username FROM users WHERE id=${CURRENT_ASSIGNED}" | tr -d '\n')
fi

# Check action log for checkout entry
CHECKOUT_LOG=$(snipeit_db_query "SELECT id, action_type, note, created_at FROM action_logs WHERE item_id=${ASSET_ID} AND item_type='App\\\\Models\\\\Asset' AND action_type='checkout' ORDER BY id DESC LIMIT 1")
CHECKOUT_LOGGED="false"
CHECKOUT_NOTE=""
if [ -n "$CHECKOUT_LOG" ]; then
    CHECKOUT_LOGGED="true"
    CHECKOUT_NOTE=$(echo "$CHECKOUT_LOG" | awk -F'\t' '{print $3}')
fi

# Build result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "asset_id": ${ASSET_ID},
  "asset_tag": "ASSET-L002",
  "is_checked_out": ${IS_CHECKED_OUT},
  "correct_user": ${CORRECT_USER},
  "current_assigned_to": "${CURRENT_ASSIGNED}",
  "current_assigned_type": "$(json_escape "$CURRENT_ASSIGNED_TYPE")",
  "target_user_id": "${TARGET_USER_ID}",
  "checked_out_user_fullname": "$(json_escape "$CHECKED_OUT_USER")",
  "checked_out_username": "$(json_escape "$CHECKED_OUT_USERNAME")",
  "initial_assigned_to": "${INITIAL_ASSIGNED}",
  "checkout_logged": ${CHECKOUT_LOGGED},
  "checkout_note": "$(json_escape "$CHECKOUT_NOTE")",
  "current_status_id": "${CURRENT_STATUS_ID}"
}
JSONEOF
)

safe_write_result "/tmp/checkout_asset_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/checkout_asset_result.json"
echo "$RESULT_JSON"
echo "=== checkout_asset export complete ==="
