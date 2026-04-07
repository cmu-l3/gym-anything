#!/bin/bash
# Setup script for Inventory Gap Filling task
# Creates the sparse INVENTORY_LOG table with planted data scenarios

set -e
echo "=== Setting up Inventory Gap Filling Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container ($ORACLE_CONTAINER) not running!"
    exit 1
fi

# --- Pre-flight: Verify DB connectivity ---
echo "[2/4] Verifying connectivity..."
wait_for_oracle_ready() {
    for i in {1..30}; do
        if oracle_query_raw "SELECT 1 FROM DUAL;" "hr" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

if ! wait_for_oracle_ready; then
    echo "ERROR: Could not connect to Oracle database"
    exit 1
fi

# --- Create Schema and Plant Data ---
echo "[3/4] Creating tables and planting data..."

# We use a PL/SQL block to drop/create to ensure clean state
oracle_query "
BEGIN
    -- Cleanup
    BEGIN EXECUTE IMMEDIATE 'DROP VIEW DAILY_INVENTORY_FULL'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE INVENTORY_LOG PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    
    -- Create Table
    EXECUTE IMMEDIATE 'CREATE TABLE INVENTORY_LOG (
        LOG_ID NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        PRODUCT_ID NUMBER,
        CHANGE_DATE DATE,
        NEW_QUANTITY NUMBER
    )';

    -- Plant Data Scenarios
    
    -- Scenario A: Product 500 (Standard gaps)
    -- Jan 01: 10
    -- Jan 10: 20
    -- Jan 25: 0
    INSERT INTO INVENTORY_LOG (PRODUCT_ID, CHANGE_DATE, NEW_QUANTITY) VALUES (500, DATE '2026-01-01', 10);
    INSERT INTO INVENTORY_LOG (PRODUCT_ID, CHANGE_DATE, NEW_QUANTITY) VALUES (500, DATE '2026-01-10', 20);
    INSERT INTO INVENTORY_LOG (PRODUCT_ID, CHANGE_DATE, NEW_QUANTITY) VALUES (500, DATE '2026-01-25', 0);
    
    -- Scenario B: Product 501 (Late start - initial zeros)
    -- Jan 15: 50
    -- Jan 16: 45
    INSERT INTO INVENTORY_LOG (PRODUCT_ID, CHANGE_DATE, NEW_QUANTITY) VALUES (501, DATE '2026-01-15', 50);
    INSERT INTO INVENTORY_LOG (PRODUCT_ID, CHANGE_DATE, NEW_QUANTITY) VALUES (501, DATE '2026-01-16', 45);
    
    -- Scenario C: Product 502 (Multiple updates same day)
    -- Jan 01: 100 (Earlier ID)
    -- Jan 01: 110 (Later ID - should prevail)
    INSERT INTO INVENTORY_LOG (PRODUCT_ID, CHANGE_DATE, NEW_QUANTITY) VALUES (502, DATE '2026-01-01', 100);
    INSERT INTO INVENTORY_LOG (PRODUCT_ID, CHANGE_DATE, NEW_QUANTITY) VALUES (502, DATE '2026-01-01', 110);
    
    COMMIT;
END;
/
" "hr"

# --- Launch DBeaver ---
echo "[4/4] Ensuring DBeaver is ready..."
if ! pgrep -f dbeaver > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/local/bin/dbeaver &" > /dev/null 2>&1 || true
    # We don't wait strictly for it to appear to save setup time, 
    # but the agent can open it.
fi

# Record start time
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="