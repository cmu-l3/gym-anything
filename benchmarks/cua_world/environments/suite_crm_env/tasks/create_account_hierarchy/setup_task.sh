#!/bin/bash
echo "=== Setting up create_account_hierarchy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# 2. Record initial account count
INITIAL_ACCOUNT_COUNT=$(get_account_count)
echo "Initial account count: $INITIAL_ACCOUNT_COUNT"
echo "$INITIAL_ACCOUNT_COUNT" > /tmp/initial_account_count.txt
chmod 666 /tmp/initial_account_count.txt 2>/dev/null || true

# 3. Verify the target accounts do not already exist (clean state)
echo "Cleaning up any pre-existing Siemens accounts..."
soft_delete_record "accounts" "name LIKE 'Siemens%'"

# 4. Ensure logged in and navigate to Accounts list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Accounts&action=index"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/hierarchy_initial.png

echo "=== create_account_hierarchy task setup complete ==="
echo "Task: Create a parent account and three subsidiary accounts linked via 'Member of'."