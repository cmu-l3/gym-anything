#!/bin/bash
echo "=== Setting up multi_company_asset_segmentation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous task runs (soft-deletes then hard-deletes)
echo "--- Cleaning up previous task data ---"
snipeit_db_query "DELETE FROM companies WHERE name LIKE 'Meridian%'" 2>/dev/null || true
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'ASSET-MT%' OR asset_tag LIKE 'ASSET-MM%' OR asset_tag LIKE 'ASSET-MH%'" 2>/dev/null || true

# Disable full company support to start clean
snipeit_db_query "UPDATE settings SET full_multiple_companies_support = 0 WHERE id = 1" 2>/dev/null || true

# 2. Find a model and status for the assets
MODEL_ID=$(snipeit_db_query "SELECT id FROM models WHERE deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
if [ -z "$MODEL_ID" ]; then
    echo "Creating generic model..."
    CAT_ID=$(snipeit_db_query "SELECT id FROM categories WHERE category_type='asset' LIMIT 1" | tr -d '[:space:]')
    MFG_ID=$(snipeit_db_query "SELECT id FROM manufacturers LIMIT 1" | tr -d '[:space:]')
    snipeit_db_query "INSERT INTO models (name, category_id, manufacturer_id, created_at) VALUES ('Holding Corp Standard', $CAT_ID, $MFG_ID, NOW())"
    MODEL_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='Holding Corp Standard' LIMIT 1" | tr -d '[:space:]')
fi

STATUS_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE type='deployable' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
if [ -z "$STATUS_ID" ]; then STATUS_ID=1; fi

# 3. Create the 9 task assets via API to ensure proper logging
echo "--- Creating task assets ---"
create_asset_api() {
    local tag="$1"
    local name="$2"
    snipeit_api POST "hardware" "{\"asset_tag\":\"$tag\",\"name\":\"$name\",\"model_id\":$MODEL_ID,\"status_id\":$STATUS_ID,\"serial\":\"SN-$tag\"}" > /dev/null 2>&1
}

create_asset_api "ASSET-MT001" "MT Consulting Laptop 1"
create_asset_api "ASSET-MT002" "MT Consulting Laptop 2"
create_asset_api "ASSET-MT003" "MT Server Node 1"
create_asset_api "ASSET-MM001" "MM Production Workstation 1"
create_asset_api "ASSET-MM002" "MM Edit Suite Display 1"
create_asset_api "ASSET-MM003" "MM Camera Equipment 1"
create_asset_api "ASSET-MH001" "MH Clinic Desktop 1"
create_asset_api "ASSET-MH002" "MH Patient Monitor 1"
create_asset_api "ASSET-MH003" "MH Lab Workstation 1"

sleep 2

# 4. Record baseline for collateral damage detection
echo "--- Recording initial state ---"
# We check COALESCE(company_id, 0) so we can compare text easily
snipeit_db_query "SELECT id, COALESCE(company_id, 0) FROM assets WHERE asset_tag NOT IN ('ASSET-MT001', 'ASSET-MT002', 'ASSET-MT003', 'ASSET-MM001', 'ASSET-MM002', 'ASSET-MM003', 'ASSET-MH001', 'ASSET-MH002', 'ASSET-MH003') AND deleted_at IS NULL ORDER BY id" > /tmp/initial_other_assets_company.txt

# 5. Ensure Firefox is open to Snipe-IT
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="