#!/bin/bash
echo "=== Setting up office_closure_asset_transfer task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Get location IDs
# ---------------------------------------------------------------
LOC_LONDON=$(snipeit_db_query "SELECT id FROM locations WHERE name='London Office' LIMIT 1" | tr -d '[:space:]')
LOC_NYC=$(snipeit_db_query "SELECT id FROM locations WHERE name='New York Office' LIMIT 1" | tr -d '[:space:]')
echo "Location IDs: London=$LOC_LONDON NYC=$LOC_NYC"
echo "$LOC_LONDON" > /tmp/transfer_london_id.txt
echo "$LOC_NYC" > /tmp/transfer_nyc_id.txt

# Get status IDs
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
SL_DEPLOYED=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Deployed' LIMIT 1" | tr -d '[:space:]')

# Get model IDs for new assets
MDL_OPT7010=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%OptiPlex 7010%' LIMIT 1" | tr -d '[:space:]')
MDL_U2723=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%U2723%' LIMIT 1" | tr -d '[:space:]')
SUP_CDW=$(snipeit_db_query "SELECT id FROM suppliers WHERE name LIKE '%CDW%' LIMIT 1" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 2. Inject additional London assets to make the task harder
# ---------------------------------------------------------------
echo "  Injecting additional London Office assets..."

# A desktop at London (deployed but not checked out)
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-D010\",\"name\":\"Dell OptiPlex 7010 - London Reception\",\"model_id\":$MDL_OPT7010,\"status_id\":$SL_DEPLOYED,\"serial\":\"DOPT7010-LON-REC\",\"purchase_date\":\"2023-09-15\",\"purchase_cost\":899.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_LONDON,\"notes\":\"London reception desk\"}"

# A monitor at London (ready to deploy)
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-M010\",\"name\":\"Dell U2723QE Monitor - London Conf Room\",\"model_id\":$MDL_U2723,\"status_id\":$SL_READY,\"serial\":\"DMON-LON-CONF1\",\"purchase_date\":\"2024-01-10\",\"purchase_cost\":549.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_LONDON,\"notes\":\"London conference room display\"}"

sleep 2

# ---------------------------------------------------------------
# 3. Record baseline state
# ---------------------------------------------------------------
echo "  Recording baseline state..."

# Count assets at London
LONDON_ASSET_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE rtd_location_id=$LOC_LONDON AND deleted_at IS NULL" | tr -d '[:space:]')
echo "$LONDON_ASSET_COUNT" > /tmp/transfer_london_asset_count.txt
echo "  London assets: $LONDON_ASSET_COUNT"

# Record London asset tags
LONDON_ASSET_TAGS=$(snipeit_db_query "SELECT asset_tag FROM assets WHERE rtd_location_id=$LOC_LONDON AND deleted_at IS NULL ORDER BY asset_tag" | tr '\n' ',' | sed 's/,$//')
echo "$LONDON_ASSET_TAGS" > /tmp/transfer_london_tags.txt
echo "  London asset tags: $LONDON_ASSET_TAGS"

# Count assets at NYC (before)
NYC_ASSET_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE rtd_location_id=$LOC_NYC AND deleted_at IS NULL" | tr -d '[:space:]')
echo "$NYC_ASSET_COUNT" > /tmp/transfer_nyc_asset_count.txt
echo "  NYC assets before: $NYC_ASSET_COUNT"

# Record checked-out London assets
LONDON_CHECKED_OUT=$(snipeit_db_query "SELECT asset_tag FROM assets WHERE rtd_location_id=$LOC_LONDON AND assigned_to IS NOT NULL AND assigned_to > 0 AND deleted_at IS NULL ORDER BY asset_tag" | tr '\n' ',' | sed 's/,$//')
echo "$LONDON_CHECKED_OUT" > /tmp/transfer_london_checked_out.txt
echo "  London checked-out assets: $LONDON_CHECKED_OUT"

# Record all non-London asset locations for false-positive check
snipeit_db_query "SELECT asset_tag, rtd_location_id FROM assets WHERE rtd_location_id != $LOC_LONDON AND deleted_at IS NULL ORDER BY asset_tag" > /tmp/transfer_non_london_baseline.txt

# Check if new asset tags already exist (cleanup)
for tag in "ASSET-D004" "ASSET-M004"; do
    if asset_exists_by_tag "$tag"; then
        echo "WARNING: $tag already exists, removing"
        snipeit_db_query "DELETE FROM assets WHERE asset_tag='$tag'"
    fi
done

# Record timestamp
date +%s > /tmp/transfer_task_start.txt

# Total asset count
TOTAL_ASSETS=$(get_asset_count)
echo "$TOTAL_ASSETS" > /tmp/transfer_total_assets.txt

# ---------------------------------------------------------------
# 4. Ensure Firefox is running and on Snipe-IT
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/transfer_initial.png

echo "=== office_closure_asset_transfer task setup complete ==="
echo "Task: Transfer all London Office assets to NYC and create 2 new NYC assets"
