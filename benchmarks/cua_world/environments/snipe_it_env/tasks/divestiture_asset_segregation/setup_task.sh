#!/bin/bash
echo "=== Setting up divestiture_asset_segregation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up potential previous runs (idempotency)
echo "  Cleaning up previous data..."
snipeit_db_query "DELETE FROM assets WHERE asset_tag IN ('AST-W1', 'AST-E1', 'AST-W2', 'AST-E2')"
snipeit_db_query "DELETE FROM users WHERE username IN ('awearable', 'benterprise')"
snipeit_db_query "DELETE FROM departments WHERE name IN ('Consumer Wearables', 'Enterprise Health')"
snipeit_db_query "DELETE FROM companies WHERE name IN ('MedTech Corporation', 'Aura Health')"

# 2. Insert Base Company
echo "  Injecting parent company..."
snipeit_db_query "INSERT INTO companies (name, created_at, updated_at) VALUES ('MedTech Corporation', DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY))"
C_MED=$(snipeit_db_query "SELECT id FROM companies WHERE name='MedTech Corporation' LIMIT 1" | tr -d '[:space:]')

# 3. Insert Departments
echo "  Injecting departments..."
snipeit_db_query "INSERT INTO departments (name, company_id, created_at, updated_at) VALUES ('Consumer Wearables', $C_MED, DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY))"
D_WEAR=$(snipeit_db_query "SELECT id FROM departments WHERE name='Consumer Wearables' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO departments (name, company_id, created_at, updated_at) VALUES ('Enterprise Health', $C_MED, DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY))"
D_ENT=$(snipeit_db_query "SELECT id FROM departments WHERE name='Enterprise Health' LIMIT 1" | tr -d '[:space:]')

# 4. Insert Users
echo "  Injecting users..."
snipeit_db_query "INSERT INTO users (first_name, last_name, username, department_id, company_id, created_at, updated_at) VALUES ('Alice', 'Wearable', 'awearable', $D_WEAR, $C_MED, DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY))"
U_WEAR=$(snipeit_db_query "SELECT id FROM users WHERE username='awearable' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO users (first_name, last_name, username, department_id, company_id, created_at, updated_at) VALUES ('Bob', 'Enterprise', 'benterprise', $D_ENT, $C_MED, DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY))"
U_ENT=$(snipeit_db_query "SELECT id FROM users WHERE username='benterprise' LIMIT 1" | tr -d '[:space:]')

# 5. Insert Assets
echo "  Injecting assets..."
MOD_ID=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]')
STAT_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE deployable=1 LIMIT 1" | tr -d '[:space:]')

# A1: Checked out to U_WEAR
snipeit_db_query "INSERT INTO assets (name, asset_tag, model_id, status_id, company_id, assigned_to, assigned_type, created_at, updated_at) VALUES ('Wearable Dept Laptop', 'AST-W1', $MOD_ID, $STAT_ID, $C_MED, $U_WEAR, 'App\\\\Models\\\\User', DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY))"

# A2: Checked out to U_ENT (Control)
snipeit_db_query "INSERT INTO assets (name, asset_tag, model_id, status_id, company_id, assigned_to, assigned_type, created_at, updated_at) VALUES ('Enterprise Dept Laptop', 'AST-E1', $MOD_ID, $STAT_ID, $C_MED, $U_ENT, 'App\\\\Models\\\\User', DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY))"

# A3: Unassigned, "Wearable" in name
snipeit_db_query "INSERT INTO assets (name, asset_tag, model_id, status_id, company_id, created_at, updated_at) VALUES ('Wearable Bio-Sensor Dev Kit', 'AST-W2', $MOD_ID, $STAT_ID, $C_MED, DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY))"

# A4: Unassigned, "Oscilloscope" (Control)
snipeit_db_query "INSERT INTO assets (name, asset_tag, model_id, status_id, company_id, created_at, updated_at) VALUES ('Standard Lab Oscilloscope', 'AST-E2', $MOD_ID, $STAT_ID, $C_MED, DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY))"

# Wait to ensure timestamps differ clearly from task start
sleep 2

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Snipe-IT is open and focused
ensure_firefox_snipeit
navigate_firefox_to "http://localhost:8000"
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== divestiture_asset_segregation task setup complete ==="