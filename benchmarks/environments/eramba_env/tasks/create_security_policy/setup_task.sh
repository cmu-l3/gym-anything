#!/bin/bash
echo "=== Setting up create_security_policy task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Verify Firefox is running on Eramba
ensure_firefox_eramba "http://localhost:8080"
sleep 2

# 2. Navigate to the Policies list page so the agent sees a clear starting point
navigate_firefox_to "http://localhost:8080/security-policies/index"
sleep 3

# 3. Take initial screenshot for logging
take_screenshot /tmp/create_security_policy_initial.png

echo "=== create_security_policy task setup complete ==="
echo "Task: Create a new 'Bring Your Own Device (BYOD) Policy' in Eramba"
echo "Agent should click 'New Policy', fill in name and description, set status to Draft, and save"
