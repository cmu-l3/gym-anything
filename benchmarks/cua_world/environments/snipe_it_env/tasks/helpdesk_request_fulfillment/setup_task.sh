#!/bin/bash
echo "=== Setting up helpdesk_request_fulfillment task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

echo "--- Seeding categories and manufacturers ---"
CAT_LAP=$(snipeit_db_query "SELECT id FROM categories WHERE name='Laptops' LIMIT 1" | tr -d '[:space:]')
CAT_MON=$(snipeit_db_query "SELECT id FROM categories WHERE name='Monitors' LIMIT 1" | tr -d '[:space:]')
CAT_TAB=$(snipeit_db_query "SELECT id FROM categories WHERE name='Tablets' LIMIT 1" | tr -d '[:space:]')

snipeit_api POST "categories" '{"name":"Peripherals","category_type":"accessory"}'
CAT_ACC=$(snipeit_db_query "SELECT id FROM categories WHERE name='Peripherals' LIMIT 1" | tr -d '[:space:]')

snipeit_api POST "categories" '{"name":"Printer Supplies","category_type":"consumable"}'
CAT_CON=$(snipeit_db_query "SELECT id FROM categories WHERE name='Printer Supplies' LIMIT 1" | tr -d '[:space:]')

MFG_LEN=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Lenovo' LIMIT 1" | tr -d '[:space:]')
MFG_DEL=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Dell' LIMIT 1" | tr -d '[:space:]')
MFG_APP=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Apple' LIMIT 1" | tr -d '[:space:]')
MFG_HP=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='HP' LIMIT 1" | tr -d '[:space:]')

echo "--- Seeding Users ---"
snipeit_api POST "users" '{"first_name":"Sarah","last_name":"Jenkins","username":"sjenkins","email":"sjenkins@example.com","password":"password"}'
snipeit_api POST "users" '{"first_name":"David","last_name":"Chen","username":"dchen","email":"dchen@example.com","password":"password"}'
snipeit_api POST "users" '{"first_name":"Maria","last_name":"Garcia","username":"mgarcia","email":"mgarcia@example.com","password":"password"}'
snipeit_api POST "users" '{"first_name":"Robert","last_name":"Taylor","username":"rtaylor","email":"rtaylor@example.com","password":"password"}'
snipeit_api POST "users" '{"first_name":"James","last_name":"Smith","username":"jsmith","email":"jsmith@example.com","password":"password"}'

USER_SJ=$(snipeit_db_query "SELECT id FROM users WHERE username='sjenkins' LIMIT 1" | tr -d '[:space:]')
USER_DC=$(snipeit_db_query "SELECT id FROM users WHERE username='dchen' LIMIT 1" | tr -d '[:space:]')
USER_MG=$(snipeit_db_query "SELECT id FROM users WHERE username='mgarcia' LIMIT 1" | tr -d '[:space:]')
USER_RT=$(snipeit_db_query "SELECT id FROM users WHERE username='rtaylor' LIMIT 1" | tr -d '[:space:]')
USER_JS=$(snipeit_db_query "SELECT id FROM users WHERE username='jsmith' LIMIT 1" | tr -d '[:space:]')

echo "$USER_SJ" > /tmp/user_sj.txt
echo "$USER_DC" > /tmp/user_dc.txt
echo "$USER_MG" > /tmp/user_mg.txt
echo "$USER_RT" > /tmp/user_rt.txt
echo "$USER_JS" > /tmp/user_js.txt

echo "--- Seeding Models ---"
snipeit_api POST "models" "{\"name\":\"Lenovo ThinkPad X1\",\"category_id\":$CAT_LAP,\"manufacturer_id\":$MFG_LEN,\"requestable\":1}"
MOD_LEN=$(snipeit_db_query "SELECT id FROM models WHERE name='Lenovo ThinkPad X1' LIMIT 1" | tr -d '[:space:]')

snipeit_api POST "models" "{\"name\":\"Dell UltraSharp 27\",\"category_id\":$CAT_MON,\"manufacturer_id\":$MFG_DEL,\"requestable\":1}"
MOD_DEL=$(snipeit_db_query "SELECT id FROM models WHERE name='Dell UltraSharp 27' LIMIT 1" | tr -d '[:space:]')

snipeit_api POST "models" "{\"name\":\"iPad Pro 12.9\",\"category_id\":$CAT_TAB,\"manufacturer_id\":$MFG_APP,\"requestable\":1}"
MOD_IPA=$(snipeit_db_query "SELECT id FROM models WHERE name='iPad Pro 12.9' LIMIT 1" | tr -d '[:space:]')

echo "--- Seeding Assets ---"
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
snipeit_api POST "hardware" "{\"asset_tag\":\"LPT-8001\",\"name\":\"Lenovo ThinkPad X1 - Request Pool\",\"model_id\":$MOD_LEN,\"status_id\":$SL_READY}"
snipeit_api POST "hardware" "{\"asset_tag\":\"MON-8002\",\"name\":\"Dell UltraSharp 27 - Request Pool\",\"model_id\":$MOD_DEL,\"status_id\":$SL_READY}"
snipeit_api POST "hardware" "{\"asset_tag\":\"IPAD-9001\",\"name\":\"iPad Pro 12.9 - Exec Pool\",\"model_id\":$MOD_IPA,\"status_id\":$SL_READY}"

echo "--- Seeding Accessories and Consumables ---"
snipeit_api POST "accessories" "{\"name\":\"Apple Magic Mouse\",\"category_id\":$CAT_ACC,\"manufacturer_id\":$MFG_APP,\"qty\":5,\"requestable\":1}"
ACC_MOUSE=$(snipeit_db_query "SELECT id FROM accessories WHERE name='Apple Magic Mouse' LIMIT 1" | tr -d '[:space:]')
echo "$ACC_MOUSE" > /tmp/acc_mouse.txt

snipeit_api POST "consumables" "{\"name\":\"HP 64X Black Toner\",\"category_id\":$CAT_CON,\"manufacturer_id\":$MFG_HP,\"qty\":10,\"requestable\":1}"
CON_TONER=$(snipeit_db_query "SELECT id FROM consumables WHERE name='HP 64X Black Toner' LIMIT 1" | tr -d '[:space:]')
echo "$CON_TONER" > /tmp/con_toner.txt

echo "--- Creating Checkout Requests ---"
snipeit_db_query "DELETE FROM checkout_requests"

snipeit_db_query "INSERT INTO checkout_requests (user_id, requestable_id, requestable_type, quantity, created_at, updated_at) VALUES ($USER_SJ, $MOD_LEN, 'App\\\\Models\\\\AssetModel', 1, NOW(), NOW())"
snipeit_db_query "INSERT INTO checkout_requests (user_id, requestable_id, requestable_type, quantity, created_at, updated_at) VALUES ($USER_DC, $MOD_DEL, 'App\\\\Models\\\\AssetModel', 1, NOW(), NOW())"
snipeit_db_query "INSERT INTO checkout_requests (user_id, requestable_id, requestable_type, quantity, created_at, updated_at) VALUES ($USER_MG, $ACC_MOUSE, 'App\\\\Models\\\\Accessory', 1, NOW(), NOW())"
snipeit_db_query "INSERT INTO checkout_requests (user_id, requestable_id, requestable_type, quantity, created_at, updated_at) VALUES ($USER_RT, $CON_TONER, 'App\\\\Models\\\\Consumable', 1, NOW(), NOW())"
snipeit_db_query "INSERT INTO checkout_requests (user_id, requestable_id, requestable_type, quantity, created_at, updated_at) VALUES ($USER_JS, $MOD_IPA, 'App\\\\Models\\\\AssetModel', 1, NOW(), NOW())"

# Prepare Firefox
ensure_firefox_snipeit
sleep 2

# Navigate to dashboard
navigate_firefox_to "http://localhost:8000"
sleep 3

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="