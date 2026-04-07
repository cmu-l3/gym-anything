#!/bin/bash
echo "=== Setting up accidental_bulk_delete_recovery task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Create Location: MDF - Data Center
# ---------------------------------------------------------------
echo "  Creating Location..."
snipeit_api POST "locations" '{"name":"MDF - Data Center", "city":"Primary HQ"}'
LOC_MDF_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='MDF - Data Center' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
if [ -z "$LOC_MDF_ID" ] || [ "$LOC_MDF_ID" == "null" ]; then
    snipeit_db_query "INSERT INTO locations (name, created_at) VALUES ('MDF - Data Center', NOW())"
    LOC_MDF_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='MDF - Data Center' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
fi
echo "  MDF Location ID: $LOC_MDF_ID"

# ---------------------------------------------------------------
# 2. Create Models via SQL for reliability
# ---------------------------------------------------------------
echo "  Creating Models..."
CAT_NET=$(snipeit_db_query "SELECT id FROM categories WHERE name='Networking' LIMIT 1" | tr -d '[:space:]')
CAT_LAP=$(snipeit_db_query "SELECT id FROM categories WHERE name='Laptops' LIMIT 1" | tr -d '[:space:]')
[ -z "$CAT_NET" ] && CAT_NET=1
[ -z "$CAT_LAP" ] && CAT_LAP=1

snipeit_db_query "INSERT INTO models (name, category_id, created_at, updated_at) VALUES ('Cisco Catalyst 9300', $CAT_NET, NOW(), NOW())"
MOD_9300=$(snipeit_db_query "SELECT id FROM models WHERE name='Cisco Catalyst 9300' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO models (name, category_id, created_at, updated_at) VALUES ('Cisco Catalyst 9200', $CAT_NET, NOW(), NOW())"
MOD_9200=$(snipeit_db_query "SELECT id FROM models WHERE name='Cisco Catalyst 9200' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO models (name, category_id, created_at, updated_at) VALUES ('Lenovo ThinkPad T460', $CAT_LAP, NOW(), NOW())"
MOD_T460=$(snipeit_db_query "SELECT id FROM models WHERE name='Lenovo ThinkPad T460' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 3. Create Assets via API
# ---------------------------------------------------------------
echo "  Creating Assets..."
STAT_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
[ -z "$STAT_READY" ] && STAT_READY=1

# Clean up if they exist
for tag in "SW-CORE-01" "SW-CORE-02" "SW-DIST-01" "LAPT-OLD-99"; do
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='$tag'"
done

snipeit_api POST "hardware" "{\"asset_tag\":\"SW-CORE-01\",\"name\":\"Core Switch 01\",\"model_id\":$MOD_9300,\"status_id\":$STAT_READY}"
snipeit_api POST "hardware" "{\"asset_tag\":\"SW-CORE-02\",\"name\":\"Core Switch 02\",\"model_id\":$MOD_9300,\"status_id\":$STAT_READY}"
snipeit_api POST "hardware" "{\"asset_tag\":\"SW-DIST-01\",\"name\":\"Dist Switch 01\",\"model_id\":$MOD_9200,\"status_id\":$STAT_READY}"
snipeit_api POST "hardware" "{\"asset_tag\":\"LAPT-OLD-99\",\"name\":\"Old ThinkPad\",\"model_id\":$MOD_T460,\"status_id\":$STAT_READY}"

sleep 2

# ---------------------------------------------------------------
# 4. Soft-Delete the Assets (Simulate the accidental bulk delete)
# ---------------------------------------------------------------
echo "  Simulating accidental bulk deletion..."
snipeit_db_query "UPDATE assets SET deleted_at = NOW() WHERE asset_tag IN ('SW-CORE-01', 'SW-CORE-02', 'SW-DIST-01', 'LAPT-OLD-99')"

# ---------------------------------------------------------------
# 5. Record initial state & launch browser
# ---------------------------------------------------------------
date +%s > /tmp/task_start_time.txt
echo "$LOC_MDF_ID" > /tmp/target_location_id.txt

ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/accidental_bulk_delete_recovery_initial.png

echo "=== accidental_bulk_delete_recovery task setup complete ==="