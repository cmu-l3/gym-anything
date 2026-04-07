#!/bin/bash
echo "=== Setting up renew_service_contract task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Use UUIDs for IDs
ACCOUNT_ID=$(cat /proc/sys/kernel/random/uuid)
CONTRACT_ID=$(cat /proc/sys/kernel/random/uuid)

# Clean up any existing records with these names to avoid duplicates
echo "Cleaning up existing records..."
soft_delete_record "accounts" "name='Vanguard Data Systems'"
suitecrm_db_query "UPDATE aos_contracts SET deleted=1 WHERE name LIKE 'Vanguard Data Systems%'" 2>/dev/null || true
suitecrm_db_query "UPDATE contracts SET deleted=1 WHERE name LIKE 'Vanguard Data Systems%'" 2>/dev/null || true

# Insert Account
echo "Inserting Vanguard Data Systems account..."
suitecrm_db_query "INSERT INTO accounts (id, name, date_entered, date_modified, modified_user_id, created_by, deleted) VALUES ('$ACCOUNT_ID', 'Vanguard Data Systems', UTC_TIMESTAMP(), UTC_TIMESTAMP(), '1', '1', 0);"

# Insert Contract (2024 SLA) into AOS_Contracts (SuiteCRM default)
echo "Inserting 2024 SLA contract..."
suitecrm_db_query "INSERT INTO aos_contracts (id, name, date_entered, date_modified, modified_user_id, created_by, deleted, status, start_date, end_date, customer_signed_date, total_contract_value, contract_account_id) VALUES ('$CONTRACT_ID', 'Vanguard Data Systems - Enterprise SLA 2024', UTC_TIMESTAMP(), UTC_TIMESTAMP(), '1', '1', 0, 'Closed', '2024-01-01', '2024-12-31', '2023-12-15', 18000.00, '$ACCOUNT_ID');"

# Get initial contract count
INITIAL_CONTRACT_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aos_contracts WHERE deleted=0" | tr -d '[:space:]')
echo "Initial contract count: $INITIAL_CONTRACT_COUNT"
echo "$INITIAL_CONTRACT_COUNT" > /tmp/initial_contract_count.txt
chmod 666 /tmp/initial_contract_count.txt 2>/dev/null || true

# Ensure logged in and navigate to Contracts list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=AOS_Contracts&action=index"
sleep 3

# Take initial screenshot
take_screenshot /tmp/renew_contract_initial.png

echo "=== renew_service_contract task setup complete ==="