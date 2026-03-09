#!/bin/bash
echo "=== Setting up create_case task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record initial case count
INITIAL_CASE_COUNT=$(get_case_count)
echo "Initial case count: $INITIAL_CASE_COUNT"
rm -f /tmp/initial_case_count.txt 2>/dev/null || true
echo "$INITIAL_CASE_COUNT" > /tmp/initial_case_count.txt
chmod 666 /tmp/initial_case_count.txt 2>/dev/null || true

# 2. Verify the target case does not already exist
if case_exists "Data pipeline latency spike after v4.1 upgrade"; then
    echo "WARNING: Case already exists, removing"
    soft_delete_record "cases" "name='Data pipeline latency spike after v4.1 upgrade'"
fi

# 3. Ensure logged in and navigate to Cases list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Cases&action=index"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/create_case_initial.png

echo "=== create_case task setup complete ==="
echo "Task: Create a new support case for NVIDIA data pipeline latency"
echo "Agent should click Create Case and fill in the form"
