#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up fiscal_year_depreciation_setup task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Clean any pre-existing depreciation schedules matching names
# ---------------------------------------------------------------
echo "--- Cleaning any pre-existing depreciation schedules ---"
snipeit_db_query "DELETE FROM depreciations WHERE name IN ('IT Equipment - Short Life', 'IT Equipment - Standard Life', 'Peripherals');" || true

# ---------------------------------------------------------------
# 2. Clear depreciation_id from all models (ensure clean slate)
# ---------------------------------------------------------------
echo "--- Clearing depreciation assignments from all models ---"
snipeit_db_query "UPDATE models SET depreciation_id = NULL WHERE depreciation_id IS NOT NULL;" || true

# ---------------------------------------------------------------
# 3. Get model IDs for asset creation (fallback to 1 if not found)
# ---------------------------------------------------------------
echo "--- Looking up model IDs ---"
MODEL_MBP=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%MacBook Pro 14%' LIMIT 1" | tr -d '[:space:]')
MODEL_PE=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%PowerEdge R740%' LIMIT 1" | tr -d '[:space:]')
MODEL_ULTRA=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%UltraSharp%' LIMIT 1" | tr -d '[:space:]')
MODEL_TP=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%ThinkPad X1 Carbon%' LIMIT 1" | tr -d '[:space:]')

MODEL_MBP=${MODEL_MBP:-1}
MODEL_PE=${MODEL_PE:-1}
MODEL_ULTRA=${MODEL_ULTRA:-1}
MODEL_TP=${MODEL_TP:-1}

# Get a deployable status ID
STATUS_RTD=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
if [ -z "$STATUS_RTD" ]; then
    STATUS_RTD=$(snipeit_db_query "SELECT id FROM status_labels WHERE pending=0 AND deployable=1 LIMIT 1" | tr -d '[:space:]')
    STATUS_RTD=${STATUS_RTD:-1}
fi

# ---------------------------------------------------------------
# 4. Remove any pre-existing DEP assets (idempotency)
# ---------------------------------------------------------------
echo "--- Removing any pre-existing ASSET-DEP* assets ---"
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'ASSET-DEP%';" || true

# ---------------------------------------------------------------
# 5. Create 4 assets with incorrect purchase data
# ---------------------------------------------------------------
echo "--- Creating assets with incorrect purchase data ---"

# ASSET-DEP001: Finance Laptop 1 - cost=0, no date
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, purchase_cost, purchase_date, created_at, updated_at)
VALUES ('ASSET-DEP001', 'Finance Laptop 1', ${MODEL_MBP}, ${STATUS_RTD}, 0.00, NULL, NOW(), NOW());"

# ASSET-DEP002: Primary DB Server - wrong cost and wrong date
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, purchase_cost, purchase_date, created_at, updated_at)
VALUES ('ASSET-DEP002', 'Primary DB Server', ${MODEL_PE}, ${STATUS_RTD}, 500.00, '2024-12-01', NOW(), NOW());"

# ASSET-DEP003: Reception Monitor - wrong cost and wrong date
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, purchase_cost, purchase_date, created_at, updated_at)
VALUES ('ASSET-DEP003', 'Reception Monitor', ${MODEL_ULTRA}, ${STATUS_RTD}, 999.99, '2025-01-01', NOW(), NOW());"

# ASSET-DEP004: Marketing Laptop 3 - null cost, no date
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, purchase_cost, purchase_date, created_at, updated_at)
VALUES ('ASSET-DEP004', 'Marketing Laptop 3', ${MODEL_TP}, ${STATUS_RTD}, NULL, NULL, NOW(), NOW());"

# ---------------------------------------------------------------
# 6. Ensure Firefox is open to Snipe-IT dashboard
# ---------------------------------------------------------------
echo "--- Setting up Firefox ---"
ensure_firefox_snipeit
sleep 3
navigate_firefox_to "http://localhost:8000"
sleep 3
focus_firefox

# ---------------------------------------------------------------
# 7. Take initial screenshot
# ---------------------------------------------------------------
take_screenshot /tmp/task_initial_state.png
echo "=== Task setup complete ==="