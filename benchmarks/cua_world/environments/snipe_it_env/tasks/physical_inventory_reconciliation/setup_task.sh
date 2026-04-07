#!/bin/bash
echo "=== Setting up physical_inventory_reconciliation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Create dependencies (Categories, Manufacturers, Locations, Statuses)
# ---------------------------------------------------------------
CAT_ID=$(snipeit_db_query "SELECT id FROM categories WHERE category_type='asset' LIMIT 1" | tr -d '[:space:]')
MAN_ID=$(snipeit_db_query "SELECT id FROM manufacturers LIMIT 1" | tr -d '[:space:]')

# Locations
snipeit_db_query "INSERT IGNORE INTO locations (name, created_at, updated_at) VALUES ('Main Campus - Building A', NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO locations (name, created_at, updated_at) VALUES ('Main Campus - Building B', NOW(), NOW())"

LOC_A=$(snipeit_db_query "SELECT id FROM locations WHERE name='Main Campus - Building A' LIMIT 1" | tr -d '[:space:]')
LOC_B=$(snipeit_db_query "SELECT id FROM locations WHERE name='Main Campus - Building B' LIMIT 1" | tr -d '[:space:]')
echo "$LOC_B" > /tmp/loc_b_id.txt

# Statuses
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
SL_LOST=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Lost/Stolen' LIMIT 1" | tr -d '[:space:]')
echo "$SL_LOST" > /tmp/sl_lost_id.txt

# ---------------------------------------------------------------
# 2. Create Models
# ---------------------------------------------------------------
snipeit_db_query "INSERT IGNORE INTO models (name, category_id, manufacturer_id, created_at, updated_at) VALUES ('Dell Latitude 5540', $CAT_ID, $MAN_ID, NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO models (name, category_id, manufacturer_id, created_at, updated_at) VALUES ('HP EliteBook 840 G10', $CAT_ID, $MAN_ID, NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO models (name, category_id, manufacturer_id, created_at, updated_at) VALUES ('Dell U2722D', $CAT_ID, $MAN_ID, NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO models (name, category_id, manufacturer_id, created_at, updated_at) VALUES ('Lenovo ThinkPad T14s', $CAT_ID, $MAN_ID, NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO models (name, category_id, manufacturer_id, created_at, updated_at) VALUES ('Cisco Meraki MR46', $CAT_ID, $MAN_ID, NOW(), NOW())"

MOD_DELL=$(snipeit_db_query "SELECT id FROM models WHERE name='Dell Latitude 5540' LIMIT 1" | tr -d '[:space:]')
MOD_HP=$(snipeit_db_query "SELECT id FROM models WHERE name='HP EliteBook 840 G10' LIMIT 1" | tr -d '[:space:]')
MOD_MON=$(snipeit_db_query "SELECT id FROM models WHERE name='Dell U2722D' LIMIT 1" | tr -d '[:space:]')
MOD_LEN=$(snipeit_db_query "SELECT id FROM models WHERE name='Lenovo ThinkPad T14s' LIMIT 1" | tr -d '[:space:]')
MOD_CISCO=$(snipeit_db_query "SELECT id FROM models WHERE name='Cisco Meraki MR46' LIMIT 1" | tr -d '[:space:]')
echo "$MOD_CISCO" > /tmp/mod_cisco_id.txt

# ---------------------------------------------------------------
# 3. Inject Audit Assets
# ---------------------------------------------------------------
# Clean up if they exist from a previous failed run
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'ASSET-AUD%'"

echo "Injecting audit hardware assets..."
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-AUD01\",\"name\":\"Dell Latitude 5540 - Audit Unit 1\",\"model_id\":$MOD_DELL,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_A}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-AUD02\",\"name\":\"Dell Latitude 5540 - Audit Unit 2\",\"model_id\":$MOD_DELL,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_A}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-AUD03\",\"name\":\"HP EliteBook 840 - Audit Unit 3\",\"model_id\":$MOD_HP,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_A}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-AUD04\",\"name\":\"Dell U2722D Monitor - Audit Unit 4\",\"model_id\":$MOD_MON,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_A}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-AUD05\",\"name\":\"Lenovo ThinkPad T14s - Audit Unit 5\",\"model_id\":$MOD_LEN,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_B}"

sleep 2

# ---------------------------------------------------------------
# 4. Record Baseline State
# ---------------------------------------------------------------
INITIAL_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL" | tr -d '[:space:]')
echo "$INITIAL_COUNT" > /tmp/initial_asset_count.txt
echo "Initial total asset count: $INITIAL_COUNT"

# ---------------------------------------------------------------
# 5. Open GUI
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3
take_screenshot /tmp/inventory_initial.png

echo "=== physical_inventory_reconciliation task setup complete ==="