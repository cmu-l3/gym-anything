#!/bin/bash
echo "=== Setting up VDI to Laptop Workforce Migration task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

echo "Injecting task prerequisite data..."

# 1. Create Locations
snipeit_api POST "locations" '{"name":"Omaha Call Center","city":"Omaha","state":"NE"}'
snipeit_api POST "locations" '{"name":"Remote/WFH","city":"Virtual","state":"Remote"}'
LOC_OMAHA=$(snipeit_db_query "SELECT id FROM locations WHERE name='Omaha Call Center' LIMIT 1" | tr -d '[:space:]')
LOC_REMOTE=$(snipeit_db_query "SELECT id FROM locations WHERE name='Remote/WFH' LIMIT 1" | tr -d '[:space:]')

# 2. Create Department
snipeit_api POST "departments" "{\"name\":\"Customer Support\",\"location_id\":$LOC_OMAHA}"
DEPT_CS=$(snipeit_db_query "SELECT id FROM departments WHERE name='Customer Support' LIMIT 1" | tr -d '[:space:]')

# 3. Create Users
snipeit_api POST "users" "{\"first_name\":\"Alice\",\"last_name\":\"Adams\",\"username\":\"aadams\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"department_id\":$DEPT_CS,\"location_id\":$LOC_OMAHA}"
snipeit_api POST "users" "{\"first_name\":\"Bob\",\"last_name\":\"Baker\",\"username\":\"bbaker\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"department_id\":$DEPT_CS,\"location_id\":$LOC_OMAHA}"
snipeit_api POST "users" "{\"first_name\":\"Carol\",\"last_name\":\"Clark\",\"username\":\"cclark\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"department_id\":$DEPT_CS,\"location_id\":$LOC_OMAHA}"

USER_A=$(snipeit_db_query "SELECT id FROM users WHERE username='aadams' LIMIT 1" | tr -d '[:space:]')
USER_B=$(snipeit_db_query "SELECT id FROM users WHERE username='bbaker' LIMIT 1" | tr -d '[:space:]')
USER_C=$(snipeit_db_query "SELECT id FROM users WHERE username='cclark' LIMIT 1" | tr -d '[:space:]')

# 4. Manufacturers and Categories
MAN_DELL=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Dell' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MAN_DELL" ]; then
    snipeit_api POST "manufacturers" '{"name":"Dell"}'
    MAN_DELL=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Dell' LIMIT 1" | tr -d '[:space:]')
fi

MAN_JABRA=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Jabra' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MAN_JABRA" ]; then
    snipeit_api POST "manufacturers" '{"name":"Jabra"}'
    MAN_JABRA=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Jabra' LIMIT 1" | tr -d '[:space:]')
fi

CAT_TC=$(snipeit_db_query "SELECT id FROM categories WHERE name='Desktops' LIMIT 1" | tr -d '[:space:]')
CAT_LAPTOP=$(snipeit_db_query "SELECT id FROM categories WHERE name='Laptops' LIMIT 1" | tr -d '[:space:]')
CAT_ACC=$(snipeit_db_query "SELECT id FROM categories WHERE name='Headsets' LIMIT 1" | tr -d '[:space:]')
if [ -z "$CAT_ACC" ]; then
    snipeit_api POST "categories" '{"name":"Headsets","category_type":"accessory"}'
    CAT_ACC=$(snipeit_db_query "SELECT id FROM categories WHERE name='Headsets' LIMIT 1" | tr -d '[:space:]')
fi

# 5. Models
snipeit_api POST "models" "{\"name\":\"Dell Wyse 3040\",\"category_id\":$CAT_TC,\"manufacturer_id\":$MAN_DELL}"
snipeit_api POST "models" "{\"name\":\"Dell Latitude 5430\",\"category_id\":$CAT_LAPTOP,\"manufacturer_id\":$MAN_DELL}"
MOD_TC=$(snipeit_db_query "SELECT id FROM models WHERE name='Dell Wyse 3040' LIMIT 1" | tr -d '[:space:]')
MOD_LAPTOP=$(snipeit_db_query "SELECT id FROM models WHERE name='Dell Latitude 5430' LIMIT 1" | tr -d '[:space:]')

# 6. Assets
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# Laptops
snipeit_api POST "hardware" "{\"asset_tag\":\"LAP-WFH-001\",\"name\":\"WFH Laptop 1\",\"model_id\":$MOD_LAPTOP,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_OMAHA}"
snipeit_api POST "hardware" "{\"asset_tag\":\"LAP-WFH-002\",\"name\":\"WFH Laptop 2\",\"model_id\":$MOD_LAPTOP,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_OMAHA}"
snipeit_api POST "hardware" "{\"asset_tag\":\"LAP-WFH-003\",\"name\":\"WFH Laptop 3\",\"model_id\":$MOD_LAPTOP,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_OMAHA}"

# Thin Clients
snipeit_api POST "hardware" "{\"asset_tag\":\"TC-001\",\"name\":\"Thin Client 1\",\"model_id\":$MOD_TC,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_OMAHA}"
snipeit_api POST "hardware" "{\"asset_tag\":\"TC-002\",\"name\":\"Thin Client 2\",\"model_id\":$MOD_TC,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_OMAHA}"
snipeit_api POST "hardware" "{\"asset_tag\":\"TC-003\",\"name\":\"Thin Client 3\",\"model_id\":$MOD_TC,\"status_id\":$SL_READY,\"rtd_location_id\":$LOC_OMAHA}"

# 7. Accessory
snipeit_api POST "accessories" "{\"name\":\"Jabra Evolve2 65\",\"category_id\":$CAT_ACC,\"manufacturer_id\":$MAN_JABRA,\"qty\":10,\"location_id\":$LOC_OMAHA}"
ACC_JABRA=$(snipeit_db_query "SELECT id FROM accessories WHERE name='Jabra Evolve2 65' LIMIT 1" | tr -d '[:space:]')

sleep 2

# 8. Checkout Thin Clients to Users
TC1_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='TC-001' LIMIT 1" | tr -d '[:space:]')
TC2_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='TC-002' LIMIT 1" | tr -d '[:space:]')
TC3_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='TC-003' LIMIT 1" | tr -d '[:space:]')

if [ -n "$TC1_ID" ] && [ -n "$USER_A" ]; then snipeit_api POST "hardware/${TC1_ID}/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$USER_A}"; fi
if [ -n "$TC2_ID" ] && [ -n "$USER_B" ]; then snipeit_api POST "hardware/${TC2_ID}/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$USER_B}"; fi
if [ -n "$TC3_ID" ] && [ -n "$USER_C" ]; then snipeit_api POST "hardware/${TC3_ID}/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$USER_C}"; fi

# 9. Launch browser and prepare view
ensure_firefox_snipeit
navigate_firefox_to "http://localhost:8000/users"
sleep 3
take_screenshot /tmp/vdi_migration_initial.png

echo "=== Task Setup Complete ==="