#!/bin/bash
echo "=== Setting up eol_hardware_refresh_cycle task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_start_time.txt

# 1. Fetch necessary IDs from the seeded database
CAT_LAPTOPS=$(snipeit_db_query "SELECT id FROM categories WHERE name='Laptops' LIMIT 1" | tr -d '[:space:]')
CAT_MONITORS=$(snipeit_db_query "SELECT id FROM categories WHERE name='Monitors' LIMIT 1" | tr -d '[:space:]')
MDL_LAPTOP=$(snipeit_db_query "SELECT id FROM models WHERE category_id=$CAT_LAPTOPS LIMIT 1" | tr -d '[:space:]')
MDL_MONITOR=$(snipeit_db_query "SELECT id FROM models WHERE category_id=$CAT_MONITORS LIMIT 1" | tr -d '[:space:]')
STAT_DEPLOYED=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Deployed' LIMIT 1" | tr -d '[:space:]')
STAT_RTD=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# Clean up any artifacts from previous runs
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'ASSET-EOL-%' OR asset_tag LIKE 'ASSET-ACT-%' OR asset_tag LIKE 'ASSET-MON-%' OR asset_tag LIKE 'ASSET-REP-%'"
snipeit_db_query "DELETE FROM users WHERE username IN ('alice_eol', 'bob_eol', 'charlie_eol', 'dave_eol')"
snipeit_db_query "DELETE FROM status_labels WHERE name='Pending E-Waste'"

# 2. Create Target Users for the test scenario
echo "  Creating test users..."
snipeit_db_query "INSERT INTO users (first_name, last_name, username, permissions, activated) VALUES ('Alice', 'Smith', 'alice_eol', '{\"superuser\":0}', 1)"
snipeit_db_query "INSERT INTO users (first_name, last_name, username, permissions, activated) VALUES ('Bob', 'Jones', 'bob_eol', '{\"superuser\":0}', 1)"
snipeit_db_query "INSERT INTO users (first_name, last_name, username, permissions, activated) VALUES ('Charlie', 'Brown', 'charlie_eol', '{\"superuser\":0}', 1)"
snipeit_db_query "INSERT INTO users (first_name, last_name, username, permissions, activated) VALUES ('Dave', 'Davis', 'dave_eol', '{\"superuser\":0}', 1)"

U_ALICE=$(snipeit_db_query "SELECT id FROM users WHERE username='alice_eol' LIMIT 1" | tr -d '[:space:]')
U_BOB=$(snipeit_db_query "SELECT id FROM users WHERE username='bob_eol' LIMIT 1" | tr -d '[:space:]')
U_CHARLIE=$(snipeit_db_query "SELECT id FROM users WHERE username='charlie_eol' LIMIT 1" | tr -d '[:space:]')
U_DAVE=$(snipeit_db_query "SELECT id FROM users WHERE username='dave_eol' LIMIT 1" | tr -d '[:space:]')

# Export User IDs for verification
echo "$U_ALICE" > /tmp/u_alice.txt
echo "$U_BOB" > /tmp/u_bob.txt
echo "$U_CHARLIE" > /tmp/u_charlie.txt
echo "$U_DAVE" > /tmp/u_dave.txt

# 3. Inject Assets
echo "  Injecting test assets..."

# Target Assets (Must be replaced)
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-EOL-01\",\"name\":\"ThinkPad T14 Gen 1\",\"model_id\":$MDL_LAPTOP,\"status_id\":$STAT_DEPLOYED,\"purchase_date\":\"2021-05-15\",\"purchase_cost\":1100,\"notes\":\"EOL Candidate\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-EOL-02\",\"name\":\"Latitude 5410\",\"model_id\":$MDL_LAPTOP,\"status_id\":$STAT_DEPLOYED,\"purchase_date\":\"2022-01-10\",\"purchase_cost\":1200,\"notes\":\"EOL Candidate\"}"

# Constraint Asset 1: Borderline Laptop (Do NOT modify, purchased exactly 1 month after threshold)
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-ACT-01\",\"name\":\"Latitude 5420\",\"model_id\":$MDL_LAPTOP,\"status_id\":$STAT_DEPLOYED,\"purchase_date\":\"2022-07-01\",\"purchase_cost\":1300,\"notes\":\"Still Active\"}"

# Constraint Asset 2: Old Monitor (Do NOT modify, old but wrong category)
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-MON-01\",\"name\":\"Dell U2419H\",\"model_id\":$MDL_MONITOR,\"status_id\":$STAT_DEPLOYED,\"purchase_date\":\"2021-01-01\",\"purchase_cost\":250,\"notes\":\"Monitor, excluded from laptop refresh\"}"

# Assign assets to users directly via DB
echo "  Assigning assets..."
snipeit_db_query "UPDATE assets SET assigned_to=$U_ALICE, assigned_type='App\\\\Models\\\\User' WHERE asset_tag='ASSET-EOL-01'"
snipeit_db_query "UPDATE assets SET assigned_to=$U_BOB, assigned_type='App\\\\Models\\\\User' WHERE asset_tag='ASSET-EOL-02'"
snipeit_db_query "UPDATE assets SET assigned_to=$U_CHARLIE, assigned_type='App\\\\Models\\\\User' WHERE asset_tag='ASSET-ACT-01'"
snipeit_db_query "UPDATE assets SET assigned_to=$U_DAVE, assigned_type='App\\\\Models\\\\User' WHERE asset_tag='ASSET-MON-01'"

# 4. Create Replacement Pool
echo "  Creating replacement pool..."
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-REP-01\",\"name\":\"ThinkPad T14 Gen 4\",\"model_id\":$MDL_LAPTOP,\"status_id\":$STAT_RTD,\"purchase_date\":\"2026-01-15\",\"purchase_cost\":1500,\"notes\":\"Ready for Q1 Refresh\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-REP-02\",\"name\":\"ThinkPad T14 Gen 4\",\"model_id\":$MDL_LAPTOP,\"status_id\":$STAT_RTD,\"purchase_date\":\"2026-01-15\",\"purchase_cost\":1500,\"notes\":\"Ready for Q1 Refresh\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-REP-03\",\"name\":\"ThinkPad T14 Gen 4\",\"model_id\":$MDL_LAPTOP,\"status_id\":$STAT_RTD,\"purchase_date\":\"2026-01-15\",\"purchase_cost\":1500,\"notes\":\"Ready for Q1 Refresh\"}"

# 5. Launch UI
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== eol_hardware_refresh_cycle task setup complete ==="