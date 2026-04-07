#!/bin/bash
echo "=== Setting up retail_pos_location_deployment task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Get status Ready to Deploy
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
if [ -z "$SL_READY" ]; then SL_READY=1; fi

echo "Cleaning up prior task state (if any)..."
snipeit_db_query "DELETE FROM assets WHERE asset_tag IN ('POS-TERM-042', 'POS-SCAN-042', 'POS-PRNT-042', 'POS-PAY-042', 'POS-PRNT-SPARE', 'POS-PRNT-018')"
snipeit_db_query "DELETE FROM locations WHERE name IN ('Store #18 - Miami', 'Central Warehouse', 'Store #42 - Chicago')"
snipeit_db_query "DELETE FROM models WHERE name IN ('RealPOS Terminal', 'DS2208 Scanner', 'TM-T88VI Printer', 'P400 Payment Terminal')"
snipeit_db_query "DELETE FROM manufacturers WHERE name IN ('NCR', 'Zebra', 'Epson', 'Verifone')"
snipeit_db_query "DELETE FROM categories WHERE name='POS Equipment'"

echo "Creating POS Categories, Manufacturers, and Models..."
snipeit_db_query "INSERT INTO categories (name, category_type, created_at, updated_at) VALUES ('POS Equipment', 'asset', NOW(), NOW())"
CAT_POS=$(snipeit_db_query "SELECT id FROM categories WHERE name='POS Equipment' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO manufacturers (name, created_at, updated_at) VALUES ('NCR', NOW(), NOW()), ('Zebra', NOW(), NOW()), ('Epson', NOW(), NOW()), ('Verifone', NOW(), NOW())"
MFR_NCR=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='NCR' LIMIT 1" | tr -d '[:space:]')
MFR_ZEBRA=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Zebra' LIMIT 1" | tr -d '[:space:]')
MFR_EPSON=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Epson' LIMIT 1" | tr -d '[:space:]')
MFR_VERIFONE=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Verifone' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO models (name, category_id, manufacturer_id, created_at, updated_at) VALUES ('RealPOS Terminal', $CAT_POS, $MFR_NCR, NOW(), NOW()), ('DS2208 Scanner', $CAT_POS, $MFR_ZEBRA, NOW(), NOW()), ('TM-T88VI Printer', $CAT_POS, $MFR_EPSON, NOW(), NOW()), ('P400 Payment Terminal', $CAT_POS, $MFR_VERIFONE, NOW(), NOW())"
MDL_TERM=$(snipeit_db_query "SELECT id FROM models WHERE name='RealPOS Terminal' LIMIT 1" | tr -d '[:space:]')
MDL_SCAN=$(snipeit_db_query "SELECT id FROM models WHERE name='DS2208 Scanner' LIMIT 1" | tr -d '[:space:]')
MDL_PRNT=$(snipeit_db_query "SELECT id FROM models WHERE name='TM-T88VI Printer' LIMIT 1" | tr -d '[:space:]')
MDL_PAY=$(snipeit_db_query "SELECT id FROM models WHERE name='P400 Payment Terminal' LIMIT 1" | tr -d '[:space:]')

echo "Creating Warehouse and Miami Locations..."
snipeit_db_query "INSERT INTO locations (name, address, city, state, country, created_at, updated_at) VALUES ('Store #18 - Miami', '123 Ocean Dr', 'Miami', 'FL', 'US', NOW(), NOW()), ('Central Warehouse', '500 Logistics Way', 'Memphis', 'TN', 'US', NOW(), NOW())"
LOC_MIAMI=$(snipeit_db_query "SELECT id FROM locations WHERE name='Store #18 - Miami' LIMIT 1" | tr -d '[:space:]')
LOC_WH=$(snipeit_db_query "SELECT id FROM locations WHERE name='Central Warehouse' LIMIT 1" | tr -d '[:space:]')

echo "Injecting staged assets..."
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, rtd_location_id, created_at, updated_at) VALUES 
('POS-TERM-042', 'Chicago POS Term', $MDL_TERM, $SL_READY, $LOC_WH, NOW(), NOW()),
('POS-SCAN-042', 'Chicago Scanner', $MDL_SCAN, $SL_READY, $LOC_WH, NOW(), NOW()),
('POS-PRNT-042', 'Chicago Printer', $MDL_PRNT, $SL_READY, $LOC_WH, NOW(), NOW()),
('POS-PAY-042', 'Chicago Payment', $MDL_PAY, $SL_READY, $LOC_WH, NOW(), NOW()),
('POS-PRNT-SPARE', 'Spare Printer', $MDL_PRNT, $SL_READY, $LOC_WH, NOW(), NOW())"

echo "Injecting checked-out Miami printer..."
# Note: assigned_type must be exactly App\Models\Location
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, rtd_location_id, assigned_to, assigned_type, created_at, updated_at) VALUES 
('POS-PRNT-018', 'Miami Printer', $MDL_PRNT, $SL_READY, $LOC_MIAMI, $LOC_MIAMI, 'App\\\\Models\\\\Location', NOW(), NOW())"

echo "Ensuring Firefox is running and navigated to dashboard..."
ensure_firefox_snipeit
sleep 1
navigate_firefox_to "http://localhost:8000"
sleep 2

take_screenshot /tmp/task_initial.png
echo "=== Setup Complete ==="