#!/bin/bash
echo "=== Setting up create_user_with_role task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial counts
INITIAL_USER_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM users WHERE deleted=0" | tr -d '[:space:]' || echo "0")
INITIAL_ROLE_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM acl_roles WHERE deleted=0" | tr -d '[:space:]' || echo "0")

echo "Initial user count: $INITIAL_USER_COUNT"
echo "Initial role count: $INITIAL_ROLE_COUNT"

echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt
echo "$INITIAL_ROLE_COUNT" > /tmp/initial_role_count.txt
chmod 666 /tmp/initial_user_count.txt /tmp/initial_role_count.txt 2>/dev/null || true

# Clean up any existing test data to ensure a clean state
echo "Cleaning up potential existing test data..."
suitecrm_db_query "UPDATE users SET deleted=1 WHERE user_name='mchen'" 2>/dev/null || true
suitecrm_db_query "UPDATE acl_roles SET deleted=1 WHERE name='Field Sales Rep'" 2>/dev/null || true

# Ensure logged in and navigate to Home
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="