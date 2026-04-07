#!/bin/bash
echo "=== Setting up create_quote_line_items task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Ensure the "Meridian Technologies" account exists
echo "--- Ensuring Meridian Technologies account exists ---"
ACCT_EXISTS=$(suitecrm_db_query "SELECT COUNT(*) FROM accounts WHERE name='Meridian Technologies' AND deleted=0" | tr -d '[:space:]')

if [ "$ACCT_EXISTS" -eq 0 ]; then
    echo "  Creating Meridian Technologies account..."
    # Generate a UUID for the new account
    ACCT_ID=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
    suitecrm_db_query "INSERT INTO accounts (id, name, billing_address_street, billing_address_city, billing_address_state, billing_address_postalcode, billing_address_country, phone_office, industry, account_type, date_entered, date_modified, created_by, modified_user_id, deleted) VALUES ('${ACCT_ID}', 'Meridian Technologies', '4200 Commerce Boulevard', 'Austin', 'TX', '78701', 'USA', '512-555-0190', 'Technology', 'Customer', NOW(), NOW(), '1', '1', 0)"
    echo "  Created account with ID: $ACCT_ID"
else
    echo "  Meridian Technologies already exists"
fi

# 3. Clean up any previous task artifacts (quotes with the target name)
echo "--- Cleaning previous task artifacts ---"
OLD_QUOTE_IDS=$(suitecrm_db_query "SELECT id FROM aos_quotes WHERE name='Q-2024-MER-001' AND deleted=0")
for OLD_ID in $OLD_QUOTE_IDS; do
    if [ -n "$OLD_ID" ]; then
        echo "  Soft-deleting old quote: $OLD_ID"
        suitecrm_db_query "UPDATE aos_quotes SET deleted=1 WHERE id='${OLD_ID}'"
        suitecrm_db_query "UPDATE aos_products_quotes SET deleted=1 WHERE parent_id='${OLD_ID}'"
    fi
done

# 4. Record initial quote count
INITIAL_QUOTE_COUNT=$(suitecrm_count "aos_quotes" "deleted=0")
echo "$INITIAL_QUOTE_COUNT" > /tmp/initial_quote_count.txt
echo "  Initial quote count: $INITIAL_QUOTE_COUNT"

# 5. Ensure Firefox is running and logged in
echo "--- Ensuring Firefox is ready ---"
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 4

# 6. Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="