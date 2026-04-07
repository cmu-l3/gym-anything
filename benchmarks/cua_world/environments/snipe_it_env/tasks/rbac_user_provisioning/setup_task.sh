#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up RBAC User Provisioning task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Record initial state for anti-gaming
# ---------------------------------------------------------------
echo "--- Recording initial state ---"
INITIAL_USER_COUNT=$(snipeit_count "users" "deleted_at IS NULL")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt
echo "  Initial user count: $INITIAL_USER_COUNT"

INITIAL_GROUP_COUNT=$(snipeit_count "permission_groups" "1=1")
echo "$INITIAL_GROUP_COUNT" > /tmp/initial_group_count.txt
echo "  Initial group count: $INITIAL_GROUP_COUNT"

# ---------------------------------------------------------------
# 2. Verify no conflicting data exists (Idempotency)
# ---------------------------------------------------------------
echo "--- Cleaning any conflicting data ---"

# Remove any pre-existing users with our target usernames
for uname in msantos jchen ppatel; do
    snipeit_db_query "DELETE FROM users WHERE username='${uname}'" 2>/dev/null || true
done

# Remove any pre-existing groups with our target names
for gname in "Help Desk Level 1" "IT Auditor"; do
    snipeit_db_query "DELETE FROM permission_groups WHERE name='${gname}'" 2>/dev/null || true
done

# Re-record initial state after cleanup to be perfectly accurate
INITIAL_USER_COUNT=$(snipeit_count "users" "deleted_at IS NULL")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt

INITIAL_GROUP_COUNT=$(snipeit_count "permission_groups" "1=1")
echo "$INITIAL_GROUP_COUNT" > /tmp/initial_group_count.txt

# ---------------------------------------------------------------
# 3. Ensure Firefox is running and on Snipe-IT
# ---------------------------------------------------------------
echo "--- Ensuring Firefox is on Snipe-IT ---"
ensure_firefox_snipeit
sleep 3

# Navigate to dashboard
navigate_firefox_to "http://localhost:8000"
sleep 3

# Focus and maximize
focus_firefox
sleep 1

# ---------------------------------------------------------------
# 4. Take initial screenshot
# ---------------------------------------------------------------
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_initial_state.png

echo "=== RBAC User Provisioning task setup complete ==="
echo "  Initial users: $INITIAL_USER_COUNT"
echo "  Initial groups: $INITIAL_GROUP_COUNT"