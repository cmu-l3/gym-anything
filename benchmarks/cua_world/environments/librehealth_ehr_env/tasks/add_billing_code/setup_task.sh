#!/bin/bash
set -e
echo "=== Setting up Add Billing Code Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for LibreHealth to be ready
wait_for_librehealth 60

# 2. Clean State: Remove the target code if it already exists
# This ensures the agent must actually perform the task
TARGET_CODE="99458"
echo "Ensuring code $TARGET_CODE does not exist..."
librehealth_query "DELETE FROM codes WHERE code='$TARGET_CODE'" 2>/dev/null || true

# 3. Record Initial State (Anti-Gaming)
# Count existing CPT4 codes to verify count increases
INITIAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM codes c JOIN code_types ct ON c.code_type = ct.ct_id WHERE ct.ct_key = 'CPT4'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_cpt4_count
echo "Initial CPT4 code count: $INITIAL_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_time.txt

# 4. Prepare UI
# Restart Firefox at the login page to ensure a clean UI state
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 5. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target Code: $TARGET_CODE"
echo "Target Fee: 42.00"