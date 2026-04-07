#!/bin/bash
echo "=== Setting up supplier_procurement_setup task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clear any pre-existing tasks state or matching suppliers/assets
echo "--- Cleaning up existing matching data ---"
snipeit_db_query "DELETE FROM suppliers WHERE name LIKE '%Dell%' OR name LIKE '%CDW%' OR name LIKE '%SHI%' OR name LIKE '%Cisco%'"
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'PROC-00%'"

# 2. Get baseline counts
INITIAL_SUPPLIERS=$(snipeit_db_query "SELECT COUNT(*) FROM suppliers WHERE deleted_at IS NULL" | tr -d '[:space:]')
echo "$INITIAL_SUPPLIERS" > /tmp/initial_supplier_count.txt

# 3. Inject the 5 hardware assets (without supplier or order_number)
echo "--- Injecting target assets ---"
# Get valid status and model IDs to satisfy foreign key constraints
SL_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
[ -z "$SL_READY_ID" ] && SL_READY_ID=1

MDL_ID=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]')
[ -z "$MDL_ID" ] && MDL_ID=1

# Insert assets directly into DB to guarantee expected starting state
# Asset 1
snipeit_db_query "INSERT INTO assets (asset_tag, name, status_id, model_id, supplier_id, order_number, created_at, updated_at) VALUES ('PROC-001', 'Dell OptiPlex 7090 Desktop', $SL_READY_ID, $MDL_ID, NULL, NULL, NOW(), NOW())"
# Asset 2
snipeit_db_query "INSERT INTO assets (asset_tag, name, status_id, model_id, supplier_id, order_number, created_at, updated_at) VALUES ('PROC-002', 'Dell Latitude 5530 Laptop', $SL_READY_ID, $MDL_ID, NULL, NULL, NOW(), NOW())"
# Asset 3
snipeit_db_query "INSERT INTO assets (asset_tag, name, status_id, model_id, supplier_id, order_number, created_at, updated_at) VALUES ('PROC-003', 'Apple MacBook Air M2', $SL_READY_ID, $MDL_ID, NULL, NULL, NOW(), NOW())"
# Asset 4
snipeit_db_query "INSERT INTO assets (asset_tag, name, status_id, model_id, supplier_id, order_number, created_at, updated_at) VALUES ('PROC-004', 'Cisco Catalyst 9200 Switch', $SL_READY_ID, $MDL_ID, NULL, NULL, NOW(), NOW())"
# Asset 5
snipeit_db_query "INSERT INTO assets (asset_tag, name, status_id, model_id, supplier_id, order_number, created_at, updated_at) VALUES ('PROC-005', 'Windows Server 2022 Host', $SL_READY_ID, $MDL_ID, NULL, NULL, NOW(), NOW())"

# 4. Ensure Firefox is running and on Snipe-IT
ensure_firefox_snipeit
sleep 2

# 5. Navigate to Snipe-IT dashboard
navigate_firefox_to "http://localhost:8000"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== supplier_procurement_setup task setup complete ==="