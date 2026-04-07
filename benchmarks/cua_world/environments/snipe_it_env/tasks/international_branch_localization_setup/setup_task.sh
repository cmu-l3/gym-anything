#!/bin/bash
echo "=== Setting up international_branch_localization_setup task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Prepare prerequisites via API
# Ensure a "New York HQ" location exists
LOC_NY_ID=$(snipeit_api POST "locations" '{"name":"New York HQ","city":"New York","currency":"USD"}' | jq -r '.payload.id // .id // empty')
if [ -z "$LOC_NY_ID" ] || [ "$LOC_NY_ID" == "null" ]; then
    LOC_NY_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='New York HQ' LIMIT 1" | tr -d '[:space:]')
    if [ -z "$LOC_NY_ID" ]; then
        # Fallback to direct DB insert
        snipeit_db_query "INSERT INTO locations (name, city, currency, created_at, updated_at) VALUES ('New York HQ', 'New York', 'USD', NOW(), NOW())"
        LOC_NY_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='New York HQ' LIMIT 1" | tr -d '[:space:]')
    fi
fi
echo "New York HQ Location ID: $LOC_NY_ID"

# 2. Create the user Klaus Weber
snipeit_api POST "users" "{\"first_name\":\"Klaus\",\"last_name\":\"Weber\",\"username\":\"kweber\",\"password\":\"password123\",\"password_confirmation\":\"password123\",\"jobtitle\":\"Sales Associate\",\"location_id\":$LOC_NY_ID}" > /dev/null
USER_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='kweber' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
echo "Klaus Weber User ID: $USER_ID"

# 3. Ensure a MacBook Pro model exists
CAT_LAPTOPS_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Laptops' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
MAN_APPLE_ID=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Apple' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
MDL_MAC_ID=$(snipeit_api POST "models" "{\"name\":\"MacBook Pro 14\",\"category_id\":$CAT_LAPTOPS_ID,\"manufacturer_id\":$MAN_APPLE_ID}" | jq -r '.payload.id // .id // empty')
if [ -z "$MDL_MAC_ID" ] || [ "$MDL_MAC_ID" == "null" ]; then
    MDL_MAC_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='MacBook Pro 14' LIMIT 1" | tr -d '[:space:]')
fi
echo "MacBook Model ID: $MDL_MAC_ID"

# 4. Create the pre-existing asset ASSET-MAC-088
SL_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-MAC-088\",\"name\":\"Klaus MacBook\",\"model_id\":$MDL_MAC_ID,\"status_id\":$SL_READY_ID,\"rtd_location_id\":$LOC_NY_ID,\"purchase_date\":\"2024-01-15\",\"purchase_cost\":1800}" > /dev/null
ASSET_MAC_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='ASSET-MAC-088' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
echo "ASSET-MAC-088 ID: $ASSET_MAC_ID"

# Record base counts
snipeit_db_query "SELECT COUNT(*) FROM locations WHERE deleted_at IS NULL" | tr -d '[:space:]' > /tmp/base_locations_count.txt
snipeit_db_query "SELECT COUNT(*) FROM suppliers WHERE deleted_at IS NULL" | tr -d '[:space:]' > /tmp/base_suppliers_count.txt
snipeit_db_query "SELECT COUNT(*) FROM models WHERE deleted_at IS NULL" | tr -d '[:space:]' > /tmp/base_models_count.txt
snipeit_db_query "SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL" | tr -d '[:space:]' > /tmp/base_assets_count.txt

# Ensure clean state for target items
snipeit_db_query "DELETE FROM locations WHERE name='Berlin Branch'"
snipeit_db_query "DELETE FROM suppliers WHERE name='Berlin Tech Wholesale'"
snipeit_db_query "DELETE FROM models WHERE name='HP Color LaserJet Pro M479fdw'"
snipeit_db_query "DELETE FROM assets WHERE asset_tag='ASSET-BER-PRN-01'"

# 5. Start Firefox and navigate to Snipe-IT
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="