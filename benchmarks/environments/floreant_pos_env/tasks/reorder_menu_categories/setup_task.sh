#!/bin/bash
set -e
echo "=== Setting up Reorder Menu Categories task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Floreant is closed to modify DB
kill_floreant

# 2. Locate Database and Tools
DB_PATH=$(find /opt/floreantpos/database -type d -name "posdb" | head -1)
if [ -z "$DB_PATH" ]; then
    # Fallback to standard location
    DB_PATH="/opt/floreantpos/database/derby-server/posdb"
fi
echo "Database found at: $DB_PATH"

# classpath for derby tools
CP="/opt/floreantpos/lib/*:/opt/floreantpos/floreantpos.jar"

# 3. Modify DB: Set 'BEVERAGES' sort order to 99 to ensure the task requires action
# Using embedded driver requires the DB not be locked by the app
echo "Resetting BEVERAGES sort order to 99..."
cat > /tmp/setup_db.sql <<EOF
CONNECT 'jdbc:derby:$DB_PATH';
UPDATE MENU_CATEGORY SET SORT_ORDER = 99 WHERE UPPER(NAME) LIKE '%BEVERAGE%';
-- Ensure it exists if it didn't
INSERT INTO MENU_CATEGORY (ID, NAME, SORT_ORDER, VISIBLE) 
    SELECT 9999, 'BEVERAGES', 99, true 
    FROM sysibm.sysdummy1 
    WHERE NOT EXISTS (SELECT * FROM MENU_CATEGORY WHERE UPPER(NAME) LIKE '%BEVERAGE%');
DISCONNECT;
EXIT;
EOF

# Execute SQL as ga user (to keep file permissions correct)
chown ga:ga /tmp/setup_db.sql
su - ga -c "java -cp '$CP' org.apache.derby.tools.ij /tmp/setup_db.sql" > /tmp/db_setup.log 2>&1 || true

# 4. Record Initial State
echo "99" > /tmp/initial_sort_order.txt
date +%s > /tmp/task_start_time.txt

# 5. Fix permissions just in case
chown -R ga:ga /opt/floreantpos/
chmod -R 755 /opt/floreantpos/

# 6. Launch App
start_and_login

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="