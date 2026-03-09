#!/bin/bash
set -e
echo "=== Setting up create_discount_coupon task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running instance and start fresh
kill_floreant
sleep 2

# -----------------------------------------------------------------------
# Record initial coupon count from Derby database
# We need to query the DB while the app is NOT running (Derby embedded mode)
# -----------------------------------------------------------------------
echo "Recording initial coupon count..."

DB_DIR=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_DIR" ]; then
    DB_DIR=$(find /opt/floreantpos/database -type d -name "posdb" 2>/dev/null | head -1)
fi

# Build classpath for ij tool
DERBY_CP=""
for jar in /opt/floreantpos/lib/derby*.jar; do
    if [ -f "$jar" ]; then
        DERBY_CP="${DERBY_CP}:${jar}"
    fi
done
DERBY_CP="${DERBY_CP}:/opt/floreantpos/lib/*"
DERBY_CP="${DERBY_CP#:}"

# Query initial coupon count using ij
INITIAL_COUNT=0
TABLE_NAME="COUPON_AND_DISCOUNT"

if [ -n "$DB_DIR" ] && [ -d "$DB_DIR" ]; then
    # Try to determine table name if standard one fails, but assume standard for setup
    cat > /tmp/count_coupons.sql << 'SQLEOF'
CONNECT 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
SELECT COUNT(*) AS CNT FROM COUPON_AND_DISCOUNT;
DISCONNECT;
EXIT;
SQLEOF

    RESULT=$(cd /opt/floreantpos && java -cp "$DERBY_CP" org.apache.derby.tools.ij /tmp/count_coupons.sql 2>/dev/null || echo "QUERY_FAILED")
    
    # Check if failed, if so try to find table (resilience)
    if echo "$RESULT" | grep -q "QUERY_FAILED\|ERROR\|does not exist"; then
        # Just record 0 if we can't query, but save table name for export script to discover
        echo "WARNING: Could not query COUPON_AND_DISCOUNT during setup."
    else
        PARSED_COUNT=$(echo "$RESULT" | grep -oE '^[0-9]+' | head -1)
        if [ -n "$PARSED_COUNT" ]; then
            INITIAL_COUNT=$PARSED_COUNT
        fi
    fi
fi

echo "$INITIAL_COUNT" > /tmp/initial_coupon_count.txt
echo "Initial coupon count: $INITIAL_COUNT"

# Also record a hash of the DB directory for change detection
if [ -n "$DB_DIR" ]; then
    find "$DB_DIR" -type f -exec md5sum {} + | sort | md5sum > /tmp/initial_db_hash.txt
fi

# Now start Floreant POS for the agent
start_and_login
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="