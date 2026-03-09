#!/bin/bash
echo "=== Setting up add_user task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Verify Firefox is running on Eramba
ensure_firefox_eramba "http://localhost:8080"
sleep 2

# 2. Navigate to User Management section
navigate_firefox_to "http://localhost:8080/settings/access-management/users"
sleep 3

# 3. Take initial screenshot
take_screenshot /tmp/add_user_initial.png

echo "=== add_user task setup complete ==="
echo "Task: Add a new user 'Alexandra Chen' (achen) with Security Analyst role"
echo "Agent should navigate to User Management, click 'New User', fill in details, and save"
