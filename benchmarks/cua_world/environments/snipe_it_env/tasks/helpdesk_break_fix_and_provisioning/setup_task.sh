#!/bin/bash
echo "=== Setting up helpdesk_break_fix_and_provisioning task ==="

source /workspace/scripts/task_utils.sh

# Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 1. Clean up existing records to prevent clashes
snipeit_db_query "DELETE FROM users WHERE username IN ('dtaylor', 'mgarcia', 'jsmith')"
snipeit_db_query "DELETE FROM assets WHERE asset_tag IN ('LAP-DT-01', 'LAP-SPARE-01', 'MON-SPARE-01')"
snipeit_db_query "DELETE FROM accessories WHERE name='Logitech MX Master 3 Mouse'"

# 2. Extract Dependencies
COMPANY_ID=$(snipeit_db_query "SELECT id FROM companies LIMIT 1" | tr -d '[:space:]')
LOC_ID=$(snipeit_db_query "SELECT id FROM locations LIMIT 1" | tr -d '[:space:]')
CAT_LAPTOP=$(snipeit_db_query "SELECT id FROM categories WHERE name LIKE '%Laptop%' LIMIT 1" | tr -d '[:space:]')
CAT_MONITOR=$(snipeit_db_query "SELECT id FROM categories WHERE name LIKE '%Monitor%' LIMIT 1" | tr -d '[:space:]')
CAT_ACC=$(snipeit_db_query "SELECT id FROM categories WHERE category_type='accessory' LIMIT 1" | tr -d '[:space:]')

# Fallbacks in case seeded categories are missing
[ -z "$CAT_LAPTOP" ] && CAT_LAPTOP=1
[ -z "$CAT_MONITOR" ] && CAT_MONITOR=1
[ -z "$CAT_ACC" ] && CAT_ACC=1

MDL_LAPTOP=$(snipeit_db_query "SELECT id FROM models WHERE category_id=$CAT_LAPTOP LIMIT 1" | tr -d '[:space:]')
MDL_MONITOR=$(snipeit_db_query "SELECT id FROM models WHERE category_id=$CAT_MONITOR LIMIT 1" | tr -d '[:space:]')
[ -z "$MDL_LAPTOP" ] && MDL_LAPTOP=1
[ -z "$MDL_MONITOR" ] && MDL_MONITOR=1

SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# 3. Create Users
snipeit_db_query "INSERT INTO users (first_name, last_name, username, password, activated, created_at) VALUES
('David', 'Taylor', 'dtaylor', 'password123', 1, NOW()),
('Maria', 'Garcia', 'mgarcia', 'password123', 1, NOW()),
('John', 'Smith', 'jsmith', 'password123', 1, NOW())"

DTAYLOR_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='dtaylor'" | tr -d '[:space:]')
MGARCIA_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='mgarcia'" | tr -d '[:space:]')
JSMITH_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='jsmith'" | tr -d '[:space:]')

# 4. Create Assets
snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, rtd_location_id, assigned_to, assigned_type, created_at) VALUES
('LAP-DT-01', 'David Taylor Laptop', $MDL_LAPTOP, $SL_READY, $LOC_ID, $DTAYLOR_ID, 'App\\\\Models\\\\User', NOW()),
('LAP-SPARE-01', 'Spare Laptop', $MDL_LAPTOP, $SL_READY, $LOC_ID, NULL, NULL, NOW()),
('MON-SPARE-01', 'Spare Monitor', $MDL_MONITOR, $SL_READY, $LOC_ID, NULL, NULL, NOW())"

LAP_DT_01_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='LAP-DT-01'" | tr -d '[:space:]')
LAP_SPARE_01_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='LAP-SPARE-01'" | tr -d '[:space:]')
MON_SPARE_01_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='MON-SPARE-01'" | tr -d '[:space:]')

# 5. Create action log for initial checkout of LAP-DT-01 to ensure proper Snipe-IT state matching
snipeit_db_query "INSERT INTO action_logs (user_id, action_type, item_id, item_type, target_id, target_type, created_at) VALUES
(1, 'checkout', $LAP_DT_01_ID, 'App\\\\Models\\\\Asset', $DTAYLOR_ID, 'App\\\\Models\\\\User', NOW())"

# 6. Create Accessory
snipeit_db_query "INSERT INTO accessories (name, category_id, qty, min_amt, location_id, created_at) VALUES
('Logitech MX Master 3 Mouse', $CAT_ACC, 5, 1, $LOC_ID, NOW())"

ACC_ID=$(snipeit_db_query "SELECT id FROM accessories WHERE name='Logitech MX Master 3 Mouse'" | tr -d '[:space:]')

# Save ID mappings for the export script
cat << EOF > /tmp/task_ids.sh
DTAYLOR_ID=$DTAYLOR_ID
MGARCIA_ID=$MGARCIA_ID
JSMITH_ID=$JSMITH_ID
LAP_DT_01_ID=$LAP_DT_01_ID
LAP_SPARE_01_ID=$LAP_SPARE_01_ID
MON_SPARE_01_ID=$MON_SPARE_01_ID
ACC_ID=$ACC_ID
EOF

# 7. Record baseline MAX action log ID for rigorous anti-gaming verification
MAX_ACTION_ID=$(snipeit_db_query "SELECT COALESCE(MAX(id), 0) FROM action_logs" | tr -d '[:space:]')
echo "$MAX_ACTION_ID" > /tmp/max_action_id.txt

# 8. Start Snipe-IT in browser
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/helpdesk_initial.png

echo "=== setup complete ==="