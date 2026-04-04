#!/bin/bash
echo "=== Setting up create_account task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record initial account count
INITIAL_ACCOUNT_COUNT=$(get_account_count)
echo "Initial account count: $INITIAL_ACCOUNT_COUNT"
rm -f /tmp/initial_account_count.txt 2>/dev/null || true
echo "$INITIAL_ACCOUNT_COUNT" > /tmp/initial_account_count.txt
chmod 666 /tmp/initial_account_count.txt 2>/dev/null || true

# 2. Verify the target account does not already exist
if account_exists "Redwood Consulting Partners"; then
    echo "WARNING: Account Redwood Consulting Partners already exists, removing"
    soft_delete_record "accounts" "name='Redwood Consulting Partners'"
fi

# 3. Ensure logged in and navigate to Accounts list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Accounts&action=index"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/create_account_initial.png

echo "=== create_account task setup complete ==="
echo "Task: Create a new account Redwood Consulting Partners"
echo "Agent should click Create Account and fill in the form"
