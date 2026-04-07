#!/bin/bash
echo "=== Setting up supplier_bankruptcy_risk_mitigation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing records from previous runs to ensure clean state
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'APX-%' OR asset_tag LIKE 'CDW-%'"
snipeit_db_query "DELETE FROM suppliers WHERE name IN ('Apex IT Solutions', 'Apex IT Solutions (BANKRUPT)', 'CDW Direct')"

# 2. Inject target and decoy suppliers
echo "Injecting suppliers..."
snipeit_db_query "INSERT INTO suppliers (name, address, city, state, country, contact, phone, email, created_at, updated_at) VALUES ('Apex IT Solutions', '123 Fake St', 'Tech City', 'CA', 'US', 'Alice Apex', '555-0199', 'support@apexit.local', NOW(), NOW())"
APEX_ID=$(snipeit_db_query "SELECT id FROM suppliers WHERE name='Apex IT Solutions' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO suppliers (name, phone, email, created_at, updated_at) VALUES ('CDW Direct', '800-800-4239', 'support@cdw.local', NOW(), NOW())"
CDW_ID=$(snipeit_db_query "SELECT id FROM suppliers WHERE name='CDW Direct' LIMIT 1" | tr -d '[:space:]')

echo "APEX_ID: $APEX_ID"
echo "CDW_ID: $CDW_ID"
echo "$APEX_ID" > /tmp/task_apex_id.txt
echo "$CDW_ID" > /tmp/task_cdw_id.txt

# 3. Retrieve valid baseline references for relationships
MDL_ID=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]')
STAT_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# 4. Inject Assets linked to APEX (These NEED to be mitigated)
echo "Injecting APEX assets..."
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, supplier_id, warranty_months, notes, purchase_date, created_at, updated_at) VALUES ('APX-001', 'Apex Server A', $MDL_ID, $STAT_ID, $APEX_ID, 36, 'Standard issue server', '2024-01-01', NOW(), NOW())"
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, supplier_id, warranty_months, notes, purchase_date, created_at, updated_at) VALUES ('APX-002', 'Apex Switch B', $MDL_ID, $STAT_ID, $APEX_ID, 36, 'Core network switch', '2024-01-15', NOW(), NOW())"
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, supplier_id, warranty_months, notes, purchase_date, created_at, updated_at) VALUES ('APX-003', 'Apex Router C', $MDL_ID, $STAT_ID, $APEX_ID, 24, 'Edge router', '2024-02-01', NOW(), NOW())"

# 5. Inject Assets linked to CDW (These act as collateral damage checks)
echo "Injecting CDW assets..."
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, supplier_id, warranty_months, notes, purchase_date, created_at, updated_at) VALUES ('CDW-001', 'Dell Workstation', $MDL_ID, $STAT_ID, $CDW_ID, 36, 'Design team workstation', '2023-11-01', NOW(), NOW())"
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, supplier_id, warranty_months, notes, purchase_date, created_at, updated_at) VALUES ('CDW-002', 'HP Printer', $MDL_ID, $STAT_ID, $CDW_ID, 12, 'Office printer', '2024-03-10', NOW(), NOW())"

# 6. Start Firefox and focus Snipe-IT
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3

# Take initial evidence screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="