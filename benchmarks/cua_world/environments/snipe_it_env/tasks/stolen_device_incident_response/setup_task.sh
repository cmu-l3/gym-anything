#!/bin/bash
echo "=== Setting up stolen_device_incident_response task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Verify David Kim's laptop is checked out to him
# ---------------------------------------------------------------
DKIM_USER_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='dkim' AND deleted_at IS NULL" | tr -d '[:space:]')
echo "David Kim user ID: $DKIM_USER_ID"
echo "$DKIM_USER_ID" > /tmp/incident_dkim_id.txt

# Find the asset checked out to David Kim (should be ASSET-L007)
STOLEN_ASSET_ID=$(snipeit_db_query "SELECT id FROM assets WHERE assigned_to=$DKIM_USER_ID AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
STOLEN_ASSET_TAG=$(snipeit_db_query "SELECT asset_tag FROM assets WHERE id=$STOLEN_ASSET_ID AND deleted_at IS NULL" | tr -d '[:space:]')
echo "Stolen asset: id=$STOLEN_ASSET_ID tag=$STOLEN_ASSET_TAG"
echo "$STOLEN_ASSET_ID" > /tmp/incident_stolen_id.txt
echo "$STOLEN_ASSET_TAG" > /tmp/incident_stolen_tag.txt

# Verify it's checked out
STOLEN_STATUS=$(snipeit_db_query "SELECT assigned_to FROM assets WHERE id=$STOLEN_ASSET_ID AND deleted_at IS NULL" | tr -d '[:space:]')
echo "  Currently assigned_to: $STOLEN_STATUS"

# If not checked out to dkim, force checkout
if [ "$STOLEN_STATUS" != "$DKIM_USER_ID" ]; then
    echo "  Asset not checked out to dkim, checking out..."
    snipeit_api POST "hardware/$STOLEN_ASSET_ID/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$DKIM_USER_ID,\"note\":\"DevOps workstation assignment\"}"
    sleep 2
fi

# ---------------------------------------------------------------
# 2. Verify replacement asset ASSET-L009 is available
# ---------------------------------------------------------------
REPLACEMENT_ASSET_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='ASSET-L009' AND deleted_at IS NULL" | tr -d '[:space:]')
REPLACEMENT_STATUS=$(snipeit_db_query "SELECT assigned_to FROM assets WHERE id=$REPLACEMENT_ASSET_ID AND deleted_at IS NULL" | tr -d '[:space:]')
echo "Replacement asset ASSET-L009: id=$REPLACEMENT_ASSET_ID assigned_to=$REPLACEMENT_STATUS"
echo "$REPLACEMENT_ASSET_ID" > /tmp/incident_replacement_id.txt

# If checked out, check it in
if [ -n "$REPLACEMENT_STATUS" ] && [ "$REPLACEMENT_STATUS" != "NULL" ] && [ "$REPLACEMENT_STATUS" != "0" ]; then
    echo "  ASSET-L009 is checked out, checking in..."
    snipeit_api POST "hardware/$REPLACEMENT_ASSET_ID/checkin" '{"note":"Reset for task setup"}'
    sleep 2
fi

# ---------------------------------------------------------------
# 3. Remove insurance asset if it exists
# ---------------------------------------------------------------
if asset_exists_by_tag "ASSET-L012"; then
    echo "WARNING: ASSET-L012 already exists, removing"
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='ASSET-L012'"
fi

# ---------------------------------------------------------------
# 4. Record baseline state
# ---------------------------------------------------------------
echo "  Recording baseline state..."

# Get status label IDs
SL_LOST_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Lost/Stolen' LIMIT 1" | tr -d '[:space:]')
echo "$SL_LOST_ID" > /tmp/incident_lost_status_id.txt

# Record the original status of the stolen asset
ORIGINAL_STATUS_ID=$(snipeit_db_query "SELECT status_id FROM assets WHERE id=$STOLEN_ASSET_ID AND deleted_at IS NULL" | tr -d '[:space:]')
ORIGINAL_STATUS_NAME=$(snipeit_db_query "SELECT sl.name FROM assets a JOIN status_labels sl ON a.status_id=sl.id WHERE a.id=$STOLEN_ASSET_ID AND a.deleted_at IS NULL" | tr -d '\n')
echo "$ORIGINAL_STATUS_ID" > /tmp/incident_original_status.txt
echo "  Original status: $ORIGINAL_STATUS_NAME (id=$ORIGINAL_STATUS_ID)"

# Record total asset count
TOTAL_ASSETS=$(get_asset_count)
echo "$TOTAL_ASSETS" > /tmp/incident_total_assets.txt

# Record a contamination asset that should NOT be modified
# Pick ASSET-L001 (Sarah Chen's laptop) as the control asset
CONTROL_STATUS=$(snipeit_db_query "SELECT status_id, assigned_to, notes FROM assets WHERE asset_tag='ASSET-L001' AND deleted_at IS NULL")
echo "$CONTROL_STATUS" > /tmp/incident_control_baseline.txt

# Record timestamp
date +%s > /tmp/incident_task_start.txt

# ---------------------------------------------------------------
# 5. Ensure Firefox is running and on Snipe-IT
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/incident_initial.png

echo "=== stolen_device_incident_response task setup complete ==="
echo "Task: Process stolen device incident for David Kim"
