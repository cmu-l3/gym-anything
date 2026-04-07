#!/bin/bash
# Setup script for recursive_demand_forecasting task
# Creates WEEKLY_SALES table and populates it with 10 weeks of data for 5 products.

set -e

echo "=== Setting up Recursive Demand Forecasting Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight checks ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

echo "[2/4] Waiting for database connectivity..."
for attempt in {1..10}; do
    if oracle_query_raw "SELECT 1 FROM DUAL;" "hr" >/dev/null 2>&1; then
        echo "  Database ready."
        break
    fi
    echo "  Waiting for database..."
    sleep 5
done

# --- Clean up old objects ---
echo "[3/4] Cleaning up schema..."
oracle_query "
BEGIN
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE weekly_sales PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE demand_forecast PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/" "hr" > /dev/null 2>&1

# --- Create and Populate Data ---
echo "[4/4] Creating and populating WEEKLY_SALES..."

# We use a PL/SQL block to generate patterns:
# 1. Ceramic_Bearing_50mm: Linear growth (100, 105, 110...)
# 2. Hydraulic_Seal_X2: Linear decay (500, 490, 480...)
# 3. Linear_Actuator_v1: Oscillating (200, 250, 200, 250...)
# 4. Stepper_Motor_NEMA23: Spike at week 8
# 5. Timing_Belt_GT2: Stable (300 flat)

oracle_query "
CREATE TABLE weekly_sales (
    product_name VARCHAR2(50),
    week_num NUMBER,
    qty_sold NUMBER
);

BEGIN
    -- Product 1: Linear Growth
    FOR i IN 1..10 LOOP
        INSERT INTO weekly_sales VALUES ('Ceramic_Bearing_50mm', i, 100 + (i-1)*5);
    END LOOP;

    -- Product 2: Linear Decay
    FOR i IN 1..10 LOOP
        INSERT INTO weekly_sales VALUES ('Hydraulic_Seal_X2', i, 500 - (i-1)*10);
    END LOOP;

    -- Product 3: Oscillating
    FOR i IN 1..10 LOOP
        IF MOD(i, 2) = 1 THEN
            INSERT INTO weekly_sales VALUES ('Linear_Actuator_v1', i, 200);
        ELSE
            INSERT INTO weekly_sales VALUES ('Linear_Actuator_v1', i, 250);
        END IF;
    END LOOP;

    -- Product 4: Spike
    FOR i IN 1..10 LOOP
        IF i = 8 THEN
            INSERT INTO weekly_sales VALUES ('Stepper_Motor_NEMA23', i, 600);
        ELSE
            INSERT INTO weekly_sales VALUES ('Stepper_Motor_NEMA23', i, 150);
        END IF;
    END LOOP;

    -- Product 5: Stable
    FOR i IN 1..10 LOOP
        INSERT INTO weekly_sales VALUES ('Timing_Belt_GT2', i, 300);
    END LOOP;

    COMMIT;
END;
/" "hr" > /dev/null

# Verify data load
ROW_COUNT=$(get_table_count "weekly_sales" "hr")
echo "  Loaded $ROW_COUNT rows into WEEKLY_SALES (Expected: 50)."

if [ "$ROW_COUNT" -ne 50 ]; then
    echo "ERROR: Data load failed."
    exit 1
fi

# Timestamp for verification
date +%s > /tmp/task_start_timestamp

# Ensure DBeaver is available for the agent
if ! which dbeaver-ce > /dev/null 2>&1; then
    echo "Installing DBeaver..."
    sudo snap install dbeaver-ce --classic > /dev/null 2>&1 || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="