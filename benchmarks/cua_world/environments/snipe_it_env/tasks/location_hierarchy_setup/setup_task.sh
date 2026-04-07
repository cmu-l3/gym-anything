#!/bin/bash
echo "=== Setting up location_hierarchy_setup task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Clean up any previous task data if it exists
# ---------------------------------------------------------------
echo "  Cleaning up previous state..."
snipeit_db_query "DELETE FROM locations WHERE name LIKE 'West Campus Medical Center%' OR name LIKE 'WC - %' OR name = 'Staging Warehouse'"
snipeit_db_query "DELETE FROM users WHERE username = 'schen'"
for tag in "ASSET-WC01" "ASSET-WC02" "ASSET-WC03" "ASSET-WC04"; do
    snipeit_db_query "DELETE FROM assets WHERE asset_tag = '$tag'"
done

# ---------------------------------------------------------------
# 2. Get prerequisites
# ---------------------------------------------------------------
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
MDL_MONITOR=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%U2723%' LIMIT 1" | tr -d '[:space:]')
MDL_LAPTOP=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%Latitude 5540%' LIMIT 1" | tr -d '[:space:]')
MDL_DESKTOP=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%OptiPlex 7010%' LIMIT 1" | tr -d '[:space:]')
SUP_CDW=$(snipeit_db_query "SELECT id FROM suppliers WHERE name LIKE '%CDW%' LIMIT 1" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 3. Create Manager User
# ---------------------------------------------------------------
echo "  Creating manager user (Sarah Chen)..."
snipeit_api POST "users" '{"first_name":"Sarah","last_name":"Chen","username":"schen","password":"password123","password_confirmation":"password123","employee_num":"EMP-4400","email":"schen@example.com"}' > /dev/null
USER_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='schen' LIMIT 1" | tr -d '[:space:]')

if [ -z "$USER_ID" ]; then
    echo "  Fallback: Creating user via DB..."
    snipeit_db_query "INSERT INTO users (first_name, last_name, username, employee_num, email, password, activated, created_at, updated_at) VALUES ('Sarah', 'Chen', 'schen', 'EMP-4400', 'schen@example.com', 'bcrypt_hash', 1, NOW(), NOW())"
    USER_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='schen' LIMIT 1" | tr -d '[:space:]')
fi
echo "  Manager User ID: $USER_ID"

# ---------------------------------------------------------------
# 4. Create Staging Warehouse Location
# ---------------------------------------------------------------
echo "  Creating Staging Warehouse..."
snipeit_api POST "locations" '{"name":"Staging Warehouse","city":"Portland","state":"OR"}' > /dev/null
LOC_STAGING_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='Staging Warehouse' LIMIT 1" | tr -d '[:space:]')

if [ -z "$LOC_STAGING_ID" ]; then
    echo "  Fallback: Creating location via DB..."
    snipeit_db_query "INSERT INTO locations (name, city, state, created_at, updated_at) VALUES ('Staging Warehouse', 'Portland', 'OR', NOW(), NOW())"
    LOC_STAGING_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='Staging Warehouse' LIMIT 1" | tr -d '[:space:]')
fi
echo "  Staging Warehouse ID: $LOC_STAGING_ID"
echo "$LOC_STAGING_ID" > /tmp/staging_location_id.txt

# ---------------------------------------------------------------
# 5. Create Staged Assets
# ---------------------------------------------------------------
echo "  Creating staged assets..."
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-WC01\",\"name\":\"Crash Cart Monitor\",\"model_id\":$MDL_MONITOR,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_STAGING_ID,\"purchase_date\":\"2024-11-01\",\"supplier_id\":$SUP_CDW}" > /dev/null
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-WC02\",\"name\":\"Portable X-Ray Workstation\",\"model_id\":$MDL_LAPTOP,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_STAGING_ID,\"purchase_date\":\"2024-11-01\",\"supplier_id\":$SUP_CDW}" > /dev/null
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-WC03\",\"name\":\"Admin Reception Desktop\",\"model_id\":$MDL_DESKTOP,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_STAGING_ID,\"purchase_date\":\"2024-11-01\",\"supplier_id\":$SUP_CDW}" > /dev/null
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-WC04\",\"name\":\"ER Triage Laptop\",\"model_id\":$MDL_LAPTOP,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_STAGING_ID,\"purchase_date\":\"2024-11-01\",\"supplier_id\":$SUP_CDW}" > /dev/null

sleep 2

# Verify assets were created
ASSET_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE rtd_location_id=$LOC_STAGING_ID AND deleted_at IS NULL" | tr -d '[:space:]')
echo "  Staged assets created: $ASSET_COUNT"
echo "$ASSET_COUNT" > /tmp/initial_staged_asset_count.txt

# ---------------------------------------------------------------
# 6. Finalize setup
# ---------------------------------------------------------------
# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is running and on Snipe-IT
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/locations"
sleep 3
take_screenshot /tmp/location_hierarchy_initial.png

echo "=== location_hierarchy_setup task setup complete ==="