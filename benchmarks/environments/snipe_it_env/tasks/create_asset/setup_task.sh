#!/bin/bash
echo "=== Setting up create_asset task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record initial asset count
INITIAL_ASSET_COUNT=$(get_asset_count)
echo "Initial asset count: $INITIAL_ASSET_COUNT"
echo "$INITIAL_ASSET_COUNT" > /tmp/initial_asset_count.txt

# 2. Record max asset ID
MAX_ASSET_ID=$(snipeit_db_query "SELECT COALESCE(MAX(id), 0) FROM assets" | tr -d '[:space:]')
echo "Max asset ID: $MAX_ASSET_ID"
echo "$MAX_ASSET_ID" > /tmp/max_asset_id.txt

# 3. Verify the target asset tag does not already exist
if asset_exists_by_tag "ASSET-L011"; then
    echo "WARNING: Asset ASSET-L011 already exists, removing it"
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='ASSET-L011'"
fi

# 4. Ensure Firefox is running and on Snipe-IT dashboard
ensure_firefox_snipeit
sleep 2

# 5. Navigate to the Snipe-IT dashboard
navigate_firefox_to "http://localhost:8000"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/create_asset_initial.png

echo "=== create_asset task setup complete ==="
echo "Task: Create a new hardware asset ASSET-L011"
echo "Agent should navigate to Assets > Create New and fill in the form"
