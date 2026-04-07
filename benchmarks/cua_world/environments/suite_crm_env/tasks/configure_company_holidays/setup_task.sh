#!/bin/bash
echo "=== Setting up configure_company_holidays task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 2. Ensure Sarah Smith exists in the users table
echo "Checking for user Sarah Smith..."
USER_EXISTS=$(suitecrm_db_query "SELECT id FROM users WHERE first_name='Sarah' AND last_name='Smith' AND deleted=0 LIMIT 1")

if [ -z "$USER_EXISTS" ]; then
    echo "Creating user Sarah Smith..."
    SARAH_ID=$(cat /proc/sys/kernel/random/uuid)
    suitecrm_db_query "INSERT INTO users (id, user_name, first_name, last_name, status, is_admin, sugar_login, deleted) VALUES ('$SARAH_ID', 'sarah.smith', 'Sarah', 'Smith', 'Active', 0, 1, 0);"
else
    echo "User Sarah Smith already exists."
fi

# 3. Clean up any previously created holidays on these target dates to ensure a clean state
suitecrm_db_query "UPDATE holidays SET deleted=1 WHERE holiday_date IN ('2026-07-03', '2026-11-26', '2026-08-14')"

# 4. Record initial holiday count
INITIAL_HOLIDAY_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM holidays WHERE deleted=0" | tr -d '[:space:]')
echo "Initial holiday count: $INITIAL_HOLIDAY_COUNT"
echo "$INITIAL_HOLIDAY_COUNT" > /tmp/initial_holiday_count.txt
chmod 666 /tmp/initial_holiday_count.txt 2>/dev/null || true

# 5. Ensure logged in and navigate to Holidays list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Holidays&action=index"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/configure_holidays_initial.png

echo "=== configure_company_holidays task setup complete ==="