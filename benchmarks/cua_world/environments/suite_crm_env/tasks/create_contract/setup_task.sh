#!/bin/bash
echo "=== Setting up create_contract task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Prepare realistic initial state - Create the Account first
# Ensure the account exists so the agent can link the contract to it
ACCOUNT_ID="westfield-1234-5678-9012-345678901234"
echo "Ensuring target account 'Westfield Industrial Supplies' exists..."
suitecrm_db_query "DELETE FROM accounts WHERE name='Westfield Industrial Supplies';"
suitecrm_db_query "INSERT INTO accounts (id, name, date_entered, date_modified, modified_user_id, created_by, description, deleted, assigned_user_id, account_type, industry) VALUES ('$ACCOUNT_ID', 'Westfield Industrial Supplies', NOW(), NOW(), '1', '1', 'Wholesale distribution customer', 0, '1', 'Customer', 'Manufacturing');"

# 2. Record initial contract count (AOS_Contracts)
INITIAL_CONTRACT_COUNT=$(suitecrm_count "aos_contracts" "deleted=0")
echo "Initial contract count: $INITIAL_CONTRACT_COUNT"
rm -f /tmp/initial_contract_count.txt 2>/dev/null || true
echo "$INITIAL_CONTRACT_COUNT" > /tmp/initial_contract_count.txt
chmod 666 /tmp/initial_contract_count.txt 2>/dev/null || true

# 3. Save task start time for anti-gaming (ensure contract created during task)
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# 4. Verify the target contract does not already exist
count=$(suitecrm_db_query "SELECT COUNT(*) FROM aos_contracts WHERE name='Annual Maintenance Agreement 2024' AND deleted=0" | tr -d '[:space:]')
if [ "$count" -gt 0 ]; then
    echo "WARNING: Target contract already exists, removing..."
    soft_delete_record "aos_contracts" "name='Annual Maintenance Agreement 2024'"
fi

# 5. Ensure logged in and navigate to Home Dashboard
# Dropping them on Home so they must navigate through the top menu
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 6. Take initial screenshot for evidence
take_screenshot /tmp/create_contract_initial.png

echo "=== create_contract task setup complete ==="
echo "Task: Create a new Contract linked to 'Westfield Industrial Supplies'"
echo "Agent should navigate to Contracts, click Create, and fill in the form"