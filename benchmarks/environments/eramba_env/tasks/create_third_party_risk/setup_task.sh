#!/bin/bash
set -e
echo "=== Setting up create_third_party_risk task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Record initial state (count of third party risks)
# We query the third_party_risks table. If it doesn't exist, we default to 0.
INITIAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM third_party_risks WHERE deleted=0;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial Third Party Risk count: $INITIAL_COUNT"

# 3. Ensure Firefox is running and logged into Eramba
# The utils function handles starting Firefox and maximizing it
ensure_firefox_eramba "http://localhost:8080/users/login"

# 4. Wait a moment for things to settle
sleep 5

# 5. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="