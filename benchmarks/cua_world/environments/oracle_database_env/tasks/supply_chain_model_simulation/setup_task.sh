#!/bin/bash
# Setup script for Supply Chain Inventory Simulation
# Creates the logistics user and populates initial tables with deterministic data

set -e
trap 'EXIT_CODE=$?; if [ $EXIT_CODE -ne 0 ]; then echo "TASK SETUP FAILED"; fi' EXIT

echo "=== Setting up Supply Chain Simulation Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Create Logistics User and Tables ---
echo "Creating logistics user and schema objects..."
oracle_query "
-- Cleanup if exists
BEGIN
  EXECUTE IMMEDIATE 'DROP USER logistics CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Create User
CREATE USER logistics IDENTIFIED BY logistics123;
GRANT CONNECT, RESOURCE, CREATE VIEW TO logistics;
ALTER USER logistics QUOTA UNLIMITED ON USERS;

-- Connect as logistics
ALTER SESSION SET CURRENT_SCHEMA = logistics;

-- Table 1: Inventory Parameters
CREATE TABLE inventory_params (
    product_id NUMBER PRIMARY KEY,
    start_inv  NUMBER,
    safety_stock NUMBER,
    reorder_qty NUMBER
);

-- Table 2: Weekly Demand
CREATE TABLE weekly_demand (
    product_id NUMBER,
    week_no    NUMBER,
    demand_qty NUMBER,
    CONSTRAINT wd_pk PRIMARY KEY (product_id, week_no)
);

-- Populate Data
-- Product 101: Low safety stock, high reorder. 
-- Logic Check: Week 1 closes at 20 (below 50) -> Order 200. Week 2 Arr=200.
INSERT INTO inventory_params VALUES (101, 100, 50, 200);

-- Product 102: High volume, steady demand
INSERT INTO inventory_params VALUES (102, 500, 100, 500);

-- Product 103: Stockout scenario (Start 50, Demand 100)
INSERT INTO inventory_params VALUES (103, 50, 20, 100);

-- Generate 10 weeks of demand
BEGIN
    -- Product 101 demand
    INSERT INTO weekly_demand VALUES (101, 1, 80);
    INSERT INTO weekly_demand VALUES (101, 2, 50);
    INSERT INTO weekly_demand VALUES (101, 3, 60);
    INSERT INTO weekly_demand VALUES (101, 4, 70);
    INSERT INTO weekly_demand VALUES (101, 5, 80);
    INSERT INTO weekly_demand VALUES (101, 6, 90);
    INSERT INTO weekly_demand VALUES (101, 7, 100);
    INSERT INTO weekly_demand VALUES (101, 8, 50);
    INSERT INTO weekly_demand VALUES (101, 9, 60);
    INSERT INTO weekly_demand VALUES (101, 10, 70);

    -- Product 102 demand (constant 100)
    FOR i IN 1..10 LOOP
        INSERT INTO weekly_demand VALUES (102, i, 100);
    END LOOP;

    -- Product 103 demand (constant 60)
    FOR i IN 1..10 LOOP
        INSERT INTO weekly_demand VALUES (103, i, 60);
    END LOOP;
    
    COMMIT;
END;
/
" "system" > /dev/null 2>&1

# --- Record start time ---
date +%s > /tmp/task_start_time
chmod 644 /tmp/task_start_time

# --- Verify data load ---
ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM weekly_demand;" "logistics" "logistics123" | tr -d ' ')
echo "Loaded $ROW_COUNT demand records."

if [ "$ROW_COUNT" -ne 30 ]; then
    echo "ERROR: Data load failed."
    exit 1
fi

echo "=== Setup Complete ==="