#!/bin/bash
echo "=== Setting up log_call_record task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# 1. Create the account "Pinnacle Distribution Co" if it doesn't exist
ACCT_EXISTS=$(suitecrm_db_query "SELECT COUNT(*) FROM accounts WHERE name='Pinnacle Distribution Co' AND deleted=0" | tr -d '[:space:]')
if [ "$ACCT_EXISTS" = "0" ]; then
    ACCT_ID=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
    suitecrm_db_query "INSERT INTO accounts (id, name, billing_address_street, billing_address_city, billing_address_state, billing_address_postalcode, billing_address_country, phone_office, industry, account_type, date_entered, date_modified, created_by, modified_user_id, deleted) VALUES ('${ACCT_ID}', 'Pinnacle Distribution Co', '450 Commerce Boulevard', 'Atlanta', 'GA', '30301', 'USA', '(404) 555-0187', 'Transportation', 'Customer', NOW(), NOW(), '1', '1', 0)"
    echo "Created account: Pinnacle Distribution Co (ID: ${ACCT_ID})"
else
    ACCT_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='Pinnacle Distribution Co' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
    echo "Account already exists: Pinnacle Distribution Co (ID: ${ACCT_ID})"
fi

# 2. Create the contact "Rachel Morrison" if it doesn't exist
CONTACT_EXISTS=$(suitecrm_db_query "SELECT COUNT(*) FROM contacts WHERE first_name='Rachel' AND last_name='Morrison' AND deleted=0" | tr -d '[:space:]')
if [ "$CONTACT_EXISTS" = "0" ]; then
    CONTACT_ID=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
    suitecrm_db_query "INSERT INTO contacts (id, first_name, last_name, title, phone_work, date_entered, date_modified, created_by, modified_user_id, deleted) VALUES ('${CONTACT_ID}', 'Rachel', 'Morrison', 'Accounts Payable Manager', '(404) 555-0192', NOW(), NOW(), '1', '1', 0)"

    # Link contact to account
    AC_REL_ID=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
    suitecrm_db_query "INSERT INTO accounts_contacts (id, contact_id, account_id, date_modified, deleted) VALUES ('${AC_REL_ID}', '${CONTACT_ID}', '${ACCT_ID}', NOW(), 0)"

    echo "Created contact: Rachel Morrison (ID: ${CONTACT_ID})"
else
    CONTACT_ID=$(suitecrm_db_query "SELECT id FROM contacts WHERE first_name='Rachel' AND last_name='Morrison' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
    echo "Contact already exists: Rachel Morrison (ID: ${CONTACT_ID})"
fi

# 3. Clean up any pre-existing calls matching the target invoice (prevents gaming)
suitecrm_db_query "UPDATE calls SET deleted=1 WHERE name LIKE '%Invoice #4821%'"

# 4. Record initial call count
INITIAL_CALL_COUNT=$(suitecrm_count "calls" "deleted=0")
echo "Initial call count: $INITIAL_CALL_COUNT"
echo "$INITIAL_CALL_COUNT" > /tmp/initial_call_count.txt
chmod 666 /tmp/initial_call_count.txt 2>/dev/null || true

# 5. Ensure Firefox is open and logged into SuiteCRM on the Home dashboard
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== log_call_record task setup complete ==="