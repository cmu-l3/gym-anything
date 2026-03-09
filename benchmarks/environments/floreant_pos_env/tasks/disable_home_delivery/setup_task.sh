#!/bin/bash
echo "=== Setting up disable_home_delivery task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure clean state (kill app)
kill_floreant

# 2. Reset database/Ensure HOME DELIVERY is ENABLED at start
# We use Derby's ij tool to forcibly set VISIBLE=TRUE for HOME DELIVERY
echo "Resetting database state..."
export CLASSPATH=$CLASSPATH:/opt/floreantpos/lib/derby.jar:/opt/floreantpos/lib/derbytools.jar
# Note: Database path depends on installation. Usually /opt/floreantpos/database/posdb or similar.
# We find the service.properties file to locate the DB.
DB_PROP=$(find /opt/floreantpos/database -name "service.properties" | head -1)
DB_PATH=$(dirname "$DB_PROP")

# Create SQL script to enable Home Delivery
cat > /tmp/reset_db.sql << EOF
CONNECT 'jdbc:derby:$DB_PATH';
UPDATE ORDER_TYPE SET VISIBLE=TRUE WHERE NAME='HOME DELIVERY';
UPDATE ORDER_TYPE SET VISIBLE=TRUE WHERE NAME='DINE IN';
UPDATE ORDER_TYPE SET VISIBLE=TRUE WHERE NAME='TAKE OUT';
EXIT;
EOF

# Run SQL update
java org.apache.derby.tools.ij /tmp/reset_db.sql > /tmp/db_reset.log 2>&1

# 3. Start Floreant POS
start_and_login

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Take initial screenshot (Evidence that button exists)
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="