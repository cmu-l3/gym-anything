#!/bin/bash
echo "=== Setting up department_restructuring task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Record initial counts
INITIAL_DEPT_COUNT=$(snipeit_count "departments" "deleted_at IS NULL")
INITIAL_USER_COUNT=$(snipeit_count "users" "deleted_at IS NULL")
echo "Initial departments: $INITIAL_DEPT_COUNT"
echo "Initial users: $INITIAL_USER_COUNT"

# 3. Record full user -> department mapping for anti-gaming (excluding users we expect to change)
snipeit_db_query "SELECT id, department_id FROM users WHERE username NOT IN ('dmoore', 'ithompson', 'rchen', 'ppatel') AND deleted_at IS NULL ORDER BY id" > /tmp/initial_user_depts.txt
md5sum /tmp/initial_user_depts.txt | awk '{print $1}' > /tmp/initial_user_depts_hash.txt

# 4. Remove any pre-existing artifacts from failed runs
for dept in "DevOps Engineering" "Cloud Infrastructure" "Software QA"; do
    snipeit_db_query "DELETE FROM departments WHERE name='$dept'"
done
for user in "rchen" "ppatel"; do
    snipeit_db_query "DELETE FROM users WHERE username='$user'"
done

# Ensure dmoore and ithompson are in the Engineering department (reset if needed)
ENG_DEPT_ID=$(snipeit_db_query "SELECT id FROM departments WHERE name='Engineering' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
if [ -n "$ENG_DEPT_ID" ]; then
    snipeit_db_query "UPDATE users SET department_id=$ENG_DEPT_ID WHERE username IN ('dmoore', 'ithompson')"
fi

# 5. Ensure Firefox is running and navigated to Snipe-IT dashboard
ensure_firefox_snipeit
sleep 2

# Navigate to dashboard explicitly
navigate_firefox_to "http://localhost:8000"
sleep 3

# Maximize Firefox
focus_firefox
DISPLAY=:1 wmctrl -r "Snipe-IT" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="