#!/bin/bash
# Setup for soft_delete_architecture task
# Creates the initial INSURANCE_POLICIES table with realistic data

set -e
echo "=== Setting up Soft Delete Architecture Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Pre-flight: Verify HR schema connectivity ---
echo "[2/4] Verifying HR schema..."
for attempt in 1 2 3; do
    if oracle_query_raw "SELECT 1 FROM DUAL;" "hr" > /dev/null 2>&1; then
        echo "  HR schema ready."
        break
    fi
    echo "  Attempt $attempt failed, waiting 10s..."
    sleep 10
    if [ $attempt -eq 3 ]; then
        echo "ERROR: Cannot connect to HR schema"
        exit 1
    fi
done

# --- Clean up previous state ---
echo "[3/4] Cleaning up previous artifacts..."
oracle_query "
BEGIN
    BEGIN EXECUTE IMMEDIATE 'DROP VIEW insurance_policies'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE insurance_policies_base PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE insurance_policies PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/" "hr" > /dev/null 2>&1

# --- Create Initial Table and Data ---
echo "[4/4] Creating initial INSURANCE_POLICIES table and data..."

# We use a PL/SQL block to generate realistic looking data
oracle_query "
CREATE TABLE insurance_policies (
    policy_id    NUMBER(10) PRIMARY KEY,
    holder_name  VARCHAR2(100),
    policy_type  VARCHAR2(50),
    premium      NUMBER(10, 2),
    start_date   DATE
);

BEGIN
    -- Seed data
    INSERT INTO insurance_policies VALUES (1001, 'John Doe', 'AUTO', 1200.50, SYSDATE - 365);
    INSERT INTO insurance_policies VALUES (1002, 'Jane Smith', 'HOME', 850.00, SYSDATE - 200);
    INSERT INTO insurance_policies VALUES (1003, 'Robert Brown', 'LIFE', 450.75, SYSDATE - 150);
    INSERT INTO insurance_policies VALUES (1004, 'Emily Davis', 'AUTO', 1100.00, SYSDATE - 50);
    INSERT INTO insurance_policies VALUES (1005, 'Dr. Arlene Stanton', 'HEALTH', 2500.00, SYSDATE - 20);

    -- Generate bulk data
    FOR i IN 1006..1150 LOOP
        INSERT INTO insurance_policies VALUES (
            i,
            'Policy Holder ' || i,
            CASE MOD(i, 4) 
                WHEN 0 THEN 'AUTO' 
                WHEN 1 THEN 'HOME' 
                WHEN 2 THEN 'LIFE' 
                ELSE 'HEALTH' 
            END,
            ROUND(DBMS_RANDOM.VALUE(300, 3000), 2),
            SYSDATE - ROUND(DBMS_RANDOM.VALUE(1, 1000))
        );
    END LOOP;
    COMMIT;
END;
/" "hr"

# Verify row count
ROW_COUNT=$(get_table_count "insurance_policies" "hr")
echo "Created table with $ROW_COUNT rows."

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure DBeaver is ready (optional but helpful context)
if ! pgrep -f dbeaver > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper &" > /dev/null 2>&1 || true
    # We don't wait strictly for it, just ensure it's launching
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="