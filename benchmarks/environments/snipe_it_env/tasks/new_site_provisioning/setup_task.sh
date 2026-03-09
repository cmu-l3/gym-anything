#!/bin/bash
echo "=== Setting up new_site_provisioning task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Clean up any pre-existing task artifacts
# ---------------------------------------------------------------
echo "  Cleaning up previous task artifacts..."

# Remove Chicago location if exists
CHICAGO_EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM locations WHERE name LIKE '%Chicago%' AND deleted_at IS NULL" | tr -d '[:space:]')
if [ "$CHICAGO_EXISTS" -gt 0 ]; then
    echo "  Removing existing Chicago location..."
    snipeit_db_query "UPDATE locations SET deleted_at=NOW() WHERE name LIKE '%Chicago%'"
fi

# Remove Logistics department if exists
LOGISTICS_EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM departments WHERE name='Logistics' AND deleted_at IS NULL" | tr -d '[:space:]')
if [ "$LOGISTICS_EXISTS" -gt 0 ]; then
    echo "  Removing existing Logistics department..."
    snipeit_db_query "UPDATE departments SET deleted_at=NOW() WHERE name='Logistics'"
fi

# Remove trivera user if exists
TRIVERA_EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM users WHERE username='trivera' AND deleted_at IS NULL" | tr -d '[:space:]')
if [ "$TRIVERA_EXISTS" -gt 0 ]; then
    echo "  Removing existing trivera user..."
    snipeit_db_query "UPDATE users SET deleted_at=NOW() WHERE username='trivera'"
fi

# ---------------------------------------------------------------
# 2. Ensure assets are in their expected initial state
# ---------------------------------------------------------------
echo "  Verifying initial asset state..."

# ASSET-D001 and ASSET-D002 should be at HQ-A
LOC_HQA=$(snipeit_db_query "SELECT id FROM locations WHERE name LIKE '%Building A%' LIMIT 1" | tr -d '[:space:]')
echo "  HQ-A location ID: $LOC_HQA"

# Record initial locations of transfer assets
D001_INITIAL_LOC=$(snipeit_db_query "SELECT rtd_location_id FROM assets WHERE asset_tag='ASSET-D001' AND deleted_at IS NULL" | tr -d '[:space:]')
D002_INITIAL_LOC=$(snipeit_db_query "SELECT rtd_location_id FROM assets WHERE asset_tag='ASSET-D002' AND deleted_at IS NULL" | tr -d '[:space:]')
echo "  ASSET-D001 initial location: $D001_INITIAL_LOC"
echo "  ASSET-D002 initial location: $D002_INITIAL_LOC"
echo "$D001_INITIAL_LOC" > /tmp/provision_d001_loc.txt
echo "$D002_INITIAL_LOC" > /tmp/provision_d002_loc.txt

# Ensure ASSET-M002 is not checked out
M002_ASSIGNED=$(snipeit_db_query "SELECT assigned_to FROM assets WHERE asset_tag='ASSET-M002' AND deleted_at IS NULL" | tr -d '[:space:]')
if [ -n "$M002_ASSIGNED" ] && [ "$M002_ASSIGNED" != "NULL" ] && [ "$M002_ASSIGNED" != "0" ]; then
    echo "  ASSET-M002 is checked out, checking in..."
    M002_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='ASSET-M002' AND deleted_at IS NULL" | tr -d '[:space:]')
    snipeit_api POST "hardware/$M002_ID/checkin" '{"note":"Reset for task setup"}'
    sleep 2
fi

# ---------------------------------------------------------------
# 3. Record baseline state
# ---------------------------------------------------------------
echo "  Recording baseline state..."

# Location count
INITIAL_LOC_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM locations WHERE deleted_at IS NULL" | tr -d '[:space:]')
echo "$INITIAL_LOC_COUNT" > /tmp/provision_loc_count.txt

# Department count
INITIAL_DEPT_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM departments WHERE deleted_at IS NULL" | tr -d '[:space:]')
echo "$INITIAL_DEPT_COUNT" > /tmp/provision_dept_count.txt

# User count
INITIAL_USER_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL" | tr -d '[:space:]')
echo "$INITIAL_USER_COUNT" > /tmp/provision_user_count.txt

# Asset count
INITIAL_ASSET_COUNT=$(get_asset_count)
echo "$INITIAL_ASSET_COUNT" > /tmp/provision_asset_count.txt

# Record a sampling of other assets for false-positive check
snipeit_db_query "SELECT asset_tag, rtd_location_id, assigned_to FROM assets WHERE asset_tag IN ('ASSET-L001','ASSET-L004','ASSET-S001','ASSET-N001') AND deleted_at IS NULL ORDER BY asset_tag" > /tmp/provision_control_baseline.txt

# Record timestamp
date +%s > /tmp/provision_task_start.txt

# ---------------------------------------------------------------
# 4. Ensure Firefox is running and on Snipe-IT
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/provision_initial.png

echo "=== new_site_provisioning task setup complete ==="
echo "Task: Create Chicago DC location, Logistics dept, user, transfer assets, checkout monitor"
