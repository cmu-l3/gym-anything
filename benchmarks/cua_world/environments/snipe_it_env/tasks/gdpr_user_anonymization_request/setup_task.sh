#!/bin/bash
echo "=== Setting up gdpr_user_anonymization_request task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/gdpr_task_start.txt

# Get baseline IDs
LOC_BERLIN=$(snipeit_db_query "SELECT id FROM locations LIMIT 1" | tr -d '[:space:]')
MDL_MAC=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%MacBook Air%' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MDL_MAC" ]; then
    MDL_MAC=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]')
fi
SL_DEPLOYED=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Deployed' LIMIT 1" | tr -d '[:space:]')
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# Clean up any previous runs
for u in kweber srossi kwagner anon_kw anon_sr; do
    snipeit_db_query "DELETE FROM users WHERE username='$u'"
done
snipeit_db_query "DELETE FROM assets WHERE asset_tag='EU-MAC-0142'"

echo "  Creating user profiles..."

# Create Klaus Weber
snipeit_api POST "users" "{\"first_name\":\"Klaus\",\"last_name\":\"Weber\",\"username\":\"kweber\",\"email\":\"klaus.weber@example.com\",\"password\":\"password123\",\"phone\":\"+49-151-12345678\",\"address\":\"123 Main St\",\"city\":\"Berlin\",\"state\":\"BE\",\"zip\":\"10115\",\"country\":\"Germany\",\"employee_num\":\"EMP-1001\",\"activated\":1}"
USER_KWEBER_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='kweber' LIMIT 1" | tr -d '[:space:]')

# Create Sofia Rossi
snipeit_api POST "users" "{\"first_name\":\"Sofia\",\"last_name\":\"Rossi\",\"username\":\"srossi\",\"email\":\"sofia.rossi@example.com\",\"password\":\"password123\",\"phone\":\"+39-333-8765432\",\"address\":\"456 Via Roma\",\"city\":\"Rome\",\"state\":\"RM\",\"zip\":\"00100\",\"country\":\"Italy\",\"employee_num\":\"EMP-1002\",\"activated\":1}"
USER_SROSSI_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='srossi' LIMIT 1" | tr -d '[:space:]')

# Create Klaus Wagner
snipeit_api POST "users" "{\"first_name\":\"Klaus\",\"last_name\":\"Wagner\",\"username\":\"kwagner\",\"email\":\"klaus.wagner@example.com\",\"password\":\"password123\",\"phone\":\"+49-170-9876543\",\"address\":\"789 High St\",\"city\":\"Munich\",\"state\":\"BY\",\"zip\":\"80331\",\"country\":\"Germany\",\"employee_num\":\"EMP-1003\",\"activated\":1}"
USER_KWAGNER_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='kwagner' LIMIT 1" | tr -d '[:space:]')

echo "  Creating asset and checking it out..."

# Create Asset EU-MAC-0142
snipeit_api POST "hardware" "{\"asset_tag\":\"EU-MAC-0142\",\"name\":\"MacBook Air M2\",\"model_id\":$MDL_MAC,\"status_id\":$SL_READY,\"serial\":\"MAC-M2-1042\",\"purchase_date\":\"2023-01-10\",\"purchase_cost\":1199.00,\"warranty_months\":36}"
sleep 1
ASSET_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='EU-MAC-0142' LIMIT 1" | tr -d '[:space:]')

# Checkout to Klaus Weber
snipeit_api POST "hardware/${ASSET_ID}/checkout" "{\"assigned_user\":$USER_KWEBER_ID,\"checkout_to_type\":\"user\",\"status_id\":$SL_DEPLOYED}"

sleep 2

# Save IDs for export script
echo "$USER_KWEBER_ID" > /tmp/gdpr_kweber_id.txt
echo "$USER_SROSSI_ID" > /tmp/gdpr_srossi_id.txt
echo "$USER_KWAGNER_ID" > /tmp/gdpr_kwagner_id.txt
echo "$ASSET_ID" > /tmp/gdpr_asset_id.txt

# Ensure Firefox is running and on Snipe-IT
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/users"
sleep 3
take_screenshot /tmp/gdpr_initial.png

echo "=== gdpr_user_anonymization_request setup complete ==="