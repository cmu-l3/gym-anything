#!/bin/bash
# Setup script for Partition Audit Log task
# Generates a large (100k+) unpartitioned audit log table with realistic distribution

set -e

echo "=== Setting up Partition Audit Log Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Verify HR schema ---
echo "[2/4] Verifying HR schema..."
wait_for_oracle 300 || exit 1

# --- Generate Data ---
echo "[3/4] Generating 100,000+ audit log records (this may take a minute)..."

# We use a PL/SQL block with bulk processing for speed, generating realistic data
# distributed across 2021-2024.
# Note: We intentionally create it as a standard heap table (unpartitioned).

oracle_query "
BEGIN
    -- Cleanup if exists
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE employee_audit_log PURGE';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- Create table
    EXECUTE IMMEDIATE '
    CREATE TABLE employee_audit_log (
        log_id NUMBER PRIMARY KEY,
        employee_id NUMBER,
        action_type VARCHAR2(30),
        action_date DATE,
        old_value VARCHAR2(200),
        new_value VARCHAR2(200),
        changed_by VARCHAR2(50),
        ip_address VARCHAR2(15)
    )';

    -- Insert data using CTAS logic or direct insert
    -- Using INSERT SELECT FROM DUAL CONNECT BY LEVEL is fastest for this volume in XE
    INSERT /*+ APPEND */ INTO employee_audit_log
    SELECT
        level as log_id,
        ROUND(DBMS_RANDOM.VALUE(100, 206)) as employee_id,
        CASE ROUND(DBMS_RANDOM.VALUE(1,10))
            WHEN 1 THEN 'SALARY_CHANGE'
            WHEN 2 THEN 'DEPT_TRANSFER'
            WHEN 3 THEN 'PROMOTION'
            WHEN 4 THEN 'TITLE_CHANGE'
            WHEN 5 THEN 'LOGIN'
            WHEN 6 THEN 'LOGOUT'
            WHEN 7 THEN 'PROFILE_UPDATE'
            WHEN 8 THEN 'ADDRESS_CHANGE'
            WHEN 9 THEN 'REVIEW_COMPLETED'
            ELSE 'BENEFITS_UPDATE'
        END as action_type,
        -- Random date between Jan 1 2021 and Dec 31 2024
        TO_DATE('2021-01-01','YYYY-MM-DD') + DBMS_RANDOM.VALUE(0, 1460) as action_date,
        DBMS_RANDOM.STRING('A', 10) as old_value,
        DBMS_RANDOM.STRING('A', 10) as new_value,
        'ADMIN_' || ROUND(DBMS_RANDOM.VALUE(1,5)) as changed_by,
        '192.168.1.' || ROUND(DBMS_RANDOM.VALUE(1,255)) as ip_address
    FROM dual
    CONNECT BY level <= 100000;

    COMMIT;
END;
/
" "hr" > /dev/null 2>&1

# --- Record Initial State ---
echo "[4/4] Recording initial state..."

# Get exact count
INITIAL_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM employee_audit_log;" "hr" | tr -d ' ')
echo "Generated $INITIAL_COUNT records."

# Save to protected file for verification
echo "$INITIAL_COUNT" > /tmp/initial_audit_count.txt
chmod 600 /tmp/initial_audit_count.txt

# Save start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure DBeaver is ready (optional convenience)
if ! pgrep -f dbeaver > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper &" > /dev/null 2>&1 || true
    # We don't wait strictly for it, just launch it
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="