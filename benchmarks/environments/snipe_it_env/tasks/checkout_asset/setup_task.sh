#!/bin/bash
echo "=== Setting up checkout_asset task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Verify the target asset exists and is available (status: Ready to Deploy)
ASSET_STATUS=$(snipeit_db_query "SELECT status_id FROM assets WHERE asset_tag='ASSET-L002' AND deleted_at IS NULL" | tr -d '[:space:]')
echo "Asset ASSET-L002 status_id: $ASSET_STATUS"

# Ensure asset is not currently checked out (reset if needed)
ASSIGNED=$(snipeit_db_query "SELECT assigned_to FROM assets WHERE asset_tag='ASSET-L002' AND deleted_at IS NULL" | tr -d '[:space:]')
if [ -n "$ASSIGNED" ] && [ "$ASSIGNED" != "NULL" ] && [ "$ASSIGNED" != "0" ]; then
    echo "Asset is currently checked out (assigned_to=$ASSIGNED), checking it back in..."
    ASSET_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='ASSET-L002' AND deleted_at IS NULL" | tr -d '[:space:]')
    # Use API to checkin
    snipeit_api POST "hardware/${ASSET_ID}/checkin" '{"note":"Reset for task setup"}'
    sleep 2
fi

# 2. Record initial state
echo "$ASSET_STATUS" > /tmp/initial_asset_status.txt

# Record checkout log count for this asset
ASSET_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='ASSET-L002' AND deleted_at IS NULL" | tr -d '[:space:]')
echo "$ASSET_ID" > /tmp/checkout_asset_id.txt

# Record the assigned_to state before the task
INITIAL_ASSIGNED=$(snipeit_db_query "SELECT COALESCE(assigned_to, 0) FROM assets WHERE id=${ASSET_ID}" | tr -d '[:space:]')
echo "$INITIAL_ASSIGNED" > /tmp/initial_assigned_to.txt

# Get the target user ID for Michael Thompson
TARGET_USER_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='mthompson' AND deleted_at IS NULL" | tr -d '[:space:]')
echo "Target user (mthompson) ID: $TARGET_USER_ID"
echo "$TARGET_USER_ID" > /tmp/target_user_id.txt

# 3. Ensure Firefox is running and on Snipe-IT
ensure_firefox_snipeit
sleep 2

# 4. Navigate to the Snipe-IT dashboard
navigate_firefox_to "http://localhost:8000"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/checkout_asset_initial.png

echo "=== checkout_asset task setup complete ==="
echo "Task: Check out asset ASSET-L002 to Michael Thompson"
echo "Agent should find the asset and use the checkout action"
