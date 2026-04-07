#!/bin/bash
echo "=== Setting up create_invoice task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 2. Ensure the account "TechFlow Solutions" exists
ACCOUNT_EXISTS=$(suitecrm_db_query "SELECT COUNT(*) FROM accounts WHERE name='TechFlow Solutions' AND deleted=0" | tr -d '[:space:]')
if [ "$ACCOUNT_EXISTS" = "0" ]; then
    echo "Creating TechFlow Solutions account..."
    ACCOUNT_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 36)
    suitecrm_db_query "INSERT INTO accounts (id, name, billing_address_street, billing_address_city, billing_address_state, billing_address_postalcode, billing_address_country, industry, account_type, date_entered, date_modified, created_by, modified_user_id, deleted)
    VALUES ('${ACCOUNT_ID}', 'TechFlow Solutions', '500 Technology Drive', 'San Jose', 'CA', '95110', 'United States', 'Technology', 'Customer', NOW(), NOW(), '1', '1', 0)"
    echo "  Account created with ID: $ACCOUNT_ID"
else
    echo "  TechFlow Solutions account already exists"
fi

# 3. Clean up any pre-existing invoice with the same name to ensure clean start
EXISTING=$(suitecrm_db_query "SELECT COUNT(*) FROM aos_invoices WHERE name='INV-2025-TFS-001' AND deleted=0" | tr -d '[:space:]')
if [ "$EXISTING" -gt 0 ] 2>/dev/null; then
    echo "  Cleaning up pre-existing invoice with same name..."
    suitecrm_db_query "UPDATE aos_invoices SET deleted=1 WHERE name='INV-2025-TFS-001'"
fi

# 4. Ensure logged in and navigate to SuiteCRM home page
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== create_invoice task setup complete ==="