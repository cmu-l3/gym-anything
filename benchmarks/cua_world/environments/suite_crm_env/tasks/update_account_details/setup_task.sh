#!/bin/bash
echo "=== Setting up task: update_account_details ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
sleep 1

# ---------------------------------------------------------------
# 1. Prepare target account with OLD (outdated) values
# ---------------------------------------------------------------
echo "--- Preparing target account ---"

# First, clean up any previous instance of this account
suitecrm_db_query "DELETE FROM accounts WHERE name='Meridian Technologies Inc'"

# Generate a standard UUID for the new account
ACCOUNT_ID=$(cat /proc/sys/kernel/random/uuid)

# Insert the account with OLD (pre-relocation) data
suitecrm_db_query "
INSERT INTO accounts (
    id, name, date_entered, date_modified, modified_user_id, created_by,
    description, deleted, assigned_user_id,
    account_type, industry, phone_office,
    billing_address_street, billing_address_city, billing_address_state,
    billing_address_postalcode, billing_address_country
) VALUES (
    '${ACCOUNT_ID}',
    'Meridian Technologies Inc',
    NOW(), NOW(), '1', '1',
    'Original equipment manufacturer. Key account since 2019.',
    0, '1',
    'Customer', 'Electronics', '(512) 555-0198',
    '1800 South Congress Ave', 'Austin', 'TX',
    '78704', 'USA'
);"

# Verify the account was created
ACCT_CHECK=$(suitecrm_db_query "SELECT COUNT(*) FROM accounts WHERE name='Meridian Technologies Inc' AND deleted=0" | tr -d '[:space:]')
echo "Account created: $ACCT_CHECK record(s)"

# Save account ID for verification
echo "$ACCOUNT_ID" > /tmp/target_account_id.txt

# ---------------------------------------------------------------
# 2. Record initial account count (to detect accidental duplicates)
# ---------------------------------------------------------------
INITIAL_ACCOUNT_COUNT=$(get_account_count)
echo "$INITIAL_ACCOUNT_COUNT" > /tmp/initial_account_count.txt
echo "Initial account count: $INITIAL_ACCOUNT_COUNT"

# ---------------------------------------------------------------
# 3. Ensure Firefox is running and logged into SuiteCRM
# ---------------------------------------------------------------
echo "--- Ensuring SuiteCRM login ---"
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Accounts&action=index"
sleep 3

# ---------------------------------------------------------------
# 4. Take screenshot of initial state
# ---------------------------------------------------------------
echo "--- Capturing initial state ---"
take_screenshot /tmp/task_initial_state.png

# Maximize and focus Firefox
focus_firefox
sleep 1

echo "=== Task setup complete ==="
echo "Target account: Meridian Technologies Inc"
echo "Current address: 1800 South Congress Ave, Austin, TX 78704"
echo "Current phone: (512) 555-0198"
echo "Current industry: Electronics"