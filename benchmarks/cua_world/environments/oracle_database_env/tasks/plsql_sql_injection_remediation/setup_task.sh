#!/bin/bash
# Setup for PL/SQL SQL Injection Remediation Task
# Creates the vulnerable HR_LEGACY_REPORTING package

set -e

echo "=== Setting up SQL Injection Remediation Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Wait for DB and HR User ---
echo "[2/4] Waiting for HR schema..."
for i in {1..30}; do
    if oracle_query_raw "SELECT 1 FROM dual;" "hr" >/dev/null 2>&1; then
        echo "  HR schema ready."
        break
    fi
    echo "  Waiting for database..."
    sleep 2
done

# --- Create Vulnerable Package ---
echo "[3/4] Creating vulnerable package..."

# 1. Create Package Specification
oracle_query "
CREATE OR REPLACE PACKAGE hr_legacy_reporting AS
    TYPE t_emp_ref_cursor IS REF CURSOR;
    TYPE t_dept_ref_cursor IS REF CURSOR;

    -- Search employees by name pattern
    PROCEDURE search_employees(
        p_name_pattern IN VARCHAR2,
        p_results      OUT t_emp_ref_cursor
    );

    -- List departments sorted by a specific column
    PROCEDURE rank_departments(
        p_sort_col IN VARCHAR2,
        p_results  OUT t_dept_ref_cursor
    );
END hr_legacy_reporting;
/
" "hr" > /dev/null

# 2. Create Package Body (VULNERABLE)
VULN_BODY="
CREATE OR REPLACE PACKAGE BODY hr_legacy_reporting AS

    PROCEDURE search_employees(
        p_name_pattern IN VARCHAR2,
        p_results      OUT t_emp_ref_cursor
    ) IS
        v_sql VARCHAR2(1000);
    BEGIN
        -- VULNERABILITY: Direct concatenation allows injection
        -- Attack: ' OR '1'='1
        v_sql := 'SELECT employee_id, first_name, last_name, email, salary ' ||
                 'FROM employees ' ||
                 'WHERE first_name LIKE ''%' || p_name_pattern || '%'' ' ||
                 'OR last_name LIKE ''%' || p_name_pattern || '%''';
        
        OPEN p_results FOR v_sql;
    END search_employees;

    PROCEDURE rank_departments(
        p_sort_col IN VARCHAR2,
        p_results  OUT t_dept_ref_cursor
    ) IS
        v_sql VARCHAR2(1000);
    BEGIN
        -- VULNERABILITY: Direct concatenation in ORDER BY
        -- Attack: department_id UNION SELECT ...
        v_sql := 'SELECT department_id, department_name, manager_id, location_id ' ||
                 'FROM departments ' ||
                 'ORDER BY ' || p_sort_col;
        
        OPEN p_results FOR v_sql;
    END rank_departments;

END hr_legacy_reporting;
/"

# Deploy the body using a temp file to handle quotes/newlines correctly
echo "$VULN_BODY" > /tmp/vuln_pkg.sql
echo "/" >> /tmp/vuln_pkg.sql
# Use sqlplus directly to run the file
sudo docker exec -i "$ORACLE_CONTAINER" sqlplus -s hr/hr123@localhost:1521/XEPDB1 < /tmp/vuln_pkg.sql > /dev/null

# --- Save Source to Desktop ---
echo "[4/4] Saving source code for agent..."
cat > /home/ga/Desktop/vulnerable_source.sql << EOF
-- HR_LEGACY_REPORTING Package Body
-- WARNING: This code contains security vulnerabilities.

$VULN_BODY
EOF
chown ga:ga /home/ga/Desktop/vulnerable_source.sql
chmod 644 /home/ga/Desktop/vulnerable_source.sql

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="