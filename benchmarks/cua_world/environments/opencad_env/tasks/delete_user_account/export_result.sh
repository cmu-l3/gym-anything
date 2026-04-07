#!/bin/bash
echo "=== Exporting delete_user_account result ==="

source /workspace/scripts/task_utils.sh

# Capture visual state
take_screenshot /tmp/task_final.png

# Load initial state data
INITIAL_TOTAL=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")
INITIAL_SAFE=$(cat /tmp/initial_safe_users_count 2>/dev/null || echo "0")
TARGET_ID=$(cat /tmp/target_user_id 2>/dev/null || echo "0")
TARGET_EMAIL="james.rodriguez@opencad.local"

# 1. Check if target user still exists
TARGET_EXISTS_NOW=$(opencad_db_query "SELECT COUNT(*) FROM users WHERE email='${TARGET_EMAIL}'")

# 2. Check current total count
CURRENT_TOTAL=$(get_user_count)

# 3. Check if safe users still exist (should be same as initial)
CURRENT_SAFE=$(opencad_db_query "SELECT COUNT(*) FROM users WHERE email IN ('admin@opencad.local', 'dispatch@opencad.local', 'sarah.mitchell@opencad.local')")

# 4. Check for orphaned records (Bonus check: did the app clean up user_departments_temp?)
# If deleted properly via app, this should be 0. If manual DB delete (unlikely for agent), might be 1.
# Note: OpenCAD's delete logic might not cascade everywhere, but we check if the ID is gone from users.
ORPHAN_CHECK="0"
if [ "$TARGET_ID" != "0" ]; then
    ORPHAN_CHECK=$(opencad_db_query "SELECT COUNT(*) FROM user_departments_temp WHERE user_id=${TARGET_ID}")
fi

# 5. Check login status (did they actually log in?)
# We can check for a session or just rely on the outcome. 
# Let's check if the admin user has a recent 'last_login' timestamp update if the schema supports it,
# but OpenCAD might not update it reliably on every login in this version.
# Instead, we rely on the DB state change.

# Prepare JSON result
RESULT_JSON=$(cat << EOF
{
    "initial_total_users": ${INITIAL_TOTAL},
    "current_total_users": ${CURRENT_TOTAL},
    "initial_safe_users": ${INITIAL_SAFE},
    "current_safe_users": ${CURRENT_SAFE},
    "target_user_exists": ${TARGET_EXISTS_NOW},
    "target_user_id": ${TARGET_ID},
    "orphaned_records": ${ORPHAN_CHECK:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/delete_user_result.json

echo "Result saved to /tmp/delete_user_result.json"
cat /tmp/delete_user_result.json
echo "=== Export complete ==="