#!/bin/bash
echo "=== Setting up warranty_audit_remediation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Inject additional assets with varying warranty periods
#    to create a realistic audit scenario.
#    Some warranties expired, some still active.
# ---------------------------------------------------------------

# Get current status label IDs
SL_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
SL_DEPLOYED_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Deployed' LIMIT 1" | tr -d '[:space:]')
SL_REPAIR_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Out for Repair' LIMIT 1" | tr -d '[:space:]')
SL_PENDING_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Pending' LIMIT 1" | tr -d '[:space:]')

echo "Status IDs: ready=$SL_READY_ID deployed=$SL_DEPLOYED_ID repair=$SL_REPAIR_ID pending=$SL_PENDING_ID"

# Get model IDs
MDL_LAT5540=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%Latitude 5540%' LIMIT 1" | tr -d '[:space:]')
MDL_EB840=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%EliteBook 840%' LIMIT 1" | tr -d '[:space:]')
MDL_T14S=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%ThinkPad T14s%' LIMIT 1" | tr -d '[:space:]')
MDL_U2723=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%U2723%' LIMIT 1" | tr -d '[:space:]')

# Get location/supplier IDs
LOC_HQA=$(snipeit_db_query "SELECT id FROM locations WHERE name LIKE '%Building A%' LIMIT 1" | tr -d '[:space:]')
SUP_CDW=$(snipeit_db_query "SELECT id FROM suppliers WHERE name LIKE '%CDW%' LIMIT 1" | tr -d '[:space:]')

# Inject new assets with expired warranties (purchase_date + warranty < 2025-03-06)
echo "  Injecting assets with expired warranties..."

# Asset W001: Purchased 2022-01-15, warranty 24 months → expired 2024-01-15 (EXPIRED)
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-W001\",\"name\":\"Dell Latitude 5540 - Accounting Dept\",\"model_id\":$MDL_LAT5540,\"status_id\":$SL_DEPLOYED_ID,\"serial\":\"DL5540-W001-ACC\",\"purchase_date\":\"2022-01-15\",\"purchase_cost\":1199.99,\"warranty_months\":24,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Accounting department workstation\"}"

# Asset W002: Purchased 2021-06-01, warranty 36 months → expired 2024-06-01 (EXPIRED)
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-W002\",\"name\":\"HP EliteBook 840 - Legal Team\",\"model_id\":$MDL_EB840,\"status_id\":$SL_READY_ID,\"serial\":\"HP840-W002-LEG\",\"purchase_date\":\"2021-06-01\",\"purchase_cost\":1349.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Legal department pool laptop\"}"

# Asset W003: Purchased 2023-02-20, warranty 12 months → expired 2024-02-20 (EXPIRED)
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-W003\",\"name\":\"Lenovo ThinkPad T14s - Intern Pool\",\"model_id\":$MDL_T14S,\"status_id\":$SL_READY_ID,\"serial\":\"LEN-W003-INT\",\"purchase_date\":\"2023-02-20\",\"purchase_cost\":1449.99,\"warranty_months\":12,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Summer intern equipment\"}"

# Asset W004: Purchased 2024-09-01, warranty 36 months → expires 2027-09-01 (STILL ACTIVE - should NOT be modified)
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-W004\",\"name\":\"Dell Latitude 5540 - New Hire 2024\",\"model_id\":$MDL_LAT5540,\"status_id\":$SL_READY_ID,\"serial\":\"DL5540-W004-NH\",\"purchase_date\":\"2024-09-01\",\"purchase_cost\":1299.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Recent purchase, warranty active\"}"

# Asset W005: Purchased 2023-03-10, warranty 18 months → expired 2024-09-10 (EXPIRED)
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-W005\",\"name\":\"Dell Monitor U2723QE - Training Room\",\"model_id\":$MDL_U2723,\"status_id\":$SL_DEPLOYED_ID,\"serial\":\"DMON-W005-TRN\",\"purchase_date\":\"2023-03-10\",\"purchase_cost\":549.99,\"warranty_months\":18,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Training room display\"}"

sleep 2

# ---------------------------------------------------------------
# 2. Record baseline state for all assets
# ---------------------------------------------------------------
echo "  Recording baseline state..."

# Record all asset tags, statuses, and notes before the task
snipeit_db_query "SELECT asset_tag, status_id, notes, purchase_date, warranty_months FROM assets WHERE deleted_at IS NULL ORDER BY asset_tag" > /tmp/warranty_baseline_assets.txt

# Count assets currently in Pending status
INITIAL_PENDING_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE status_id=$SL_PENDING_ID AND deleted_at IS NULL" | tr -d '[:space:]')
echo "$INITIAL_PENDING_COUNT" > /tmp/warranty_initial_pending_count.txt
echo "  Initial pending count: $INITIAL_PENDING_COUNT"

# Record the injected asset IDs for verification
INJECTED_TAGS="ASSET-W001,ASSET-W002,ASSET-W003,ASSET-W004,ASSET-W005"
echo "$INJECTED_TAGS" > /tmp/warranty_injected_tags.txt

# Record which injected assets should be flagged (expired warranties)
# W001: 2022-01-15 + 24m = 2024-01-15 → EXPIRED
# W002: 2021-06-01 + 36m = 2024-06-01 → EXPIRED
# W003: 2023-02-20 + 12m = 2024-02-20 → EXPIRED
# W004: 2024-09-01 + 36m = 2027-09-01 → ACTIVE
# W005: 2023-03-10 + 18m = 2024-09-10 → EXPIRED
echo "ASSET-W001,ASSET-W002,ASSET-W003,ASSET-W005" > /tmp/warranty_expected_expired_injected.txt

# Also check existing assets for expired warranties
# ASSET-L003: 2023-06-20 + 36m = 2026-06-20 → ACTIVE
# ASSET-L010: 2020-03-15 + 36m = 2023-03-15 → EXPIRED but RETIRED status
# ASSET-L008: 2024-05-01 + 12m = 2025-05-01 → ACTIVE
# The pre-existing assets with short warranties that might be expired:
# We need to check all existing assets and compute their expiration
snipeit_db_query "SELECT asset_tag, status_id, purchase_date, warranty_months, DATE_ADD(purchase_date, INTERVAL warranty_months MONTH) as warranty_expiry FROM assets WHERE deleted_at IS NULL AND DATE_ADD(purchase_date, INTERVAL warranty_months MONTH) < '2025-03-06' ORDER BY asset_tag" > /tmp/warranty_all_expired.txt

# Record the status of ASSET-L010 (retired) - should NOT be modified
RETIRED_STATUS=$(snipeit_db_query "SELECT status_id FROM assets WHERE asset_tag='ASSET-L010' AND deleted_at IS NULL" | tr -d '[:space:]')
echo "$RETIRED_STATUS" > /tmp/warranty_retired_status.txt

# Record timestamp
date +%s > /tmp/warranty_task_start.txt

# ---------------------------------------------------------------
# 3. Ensure Firefox is running and on Snipe-IT
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/warranty_audit_initial.png

echo "=== warranty_audit_remediation task setup complete ==="
echo "Task: Identify expired warranty assets and update their status to Pending"
