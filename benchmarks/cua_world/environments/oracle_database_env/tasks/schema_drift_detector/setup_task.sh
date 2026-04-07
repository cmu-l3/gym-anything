#!/bin/bash
# Setup script for Schema Drift Detector task
# Creates HR_PROD and HR_DEV schemas and plants 5 specific structural differences

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Schema Drift Detector Task ==="

# 1. Verify Oracle is running
if ! is_oracle_running; then
    echo "Starting Oracle..."
    # Rely on env hooks, but wait if needed
    wait_for_oracle 300
fi

# 2. Drop existing schemas if they exist to ensure clean state
echo "Cleaning up old schemas..."
oracle_query "
BEGIN
    FOR user_rec IN (SELECT username FROM dba_users WHERE username IN ('HR_PROD', 'HR_DEV')) LOOP
        EXECUTE IMMEDIATE 'DROP USER ' || user_rec.username || ' CASCADE';
    END LOOP;
    
    -- Also drop the log table if it exists from previous run
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE SYSTEM.SCHEMA_DRIFT_LOG PURGE';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
END;
/" "system" "OraclePassword123"

# 3. Create Users
echo "Creating HR_PROD and HR_DEV users..."
oracle_query "
CREATE USER HR_PROD IDENTIFIED BY hr123 QUOTA UNLIMITED ON USERS;
CREATE USER HR_DEV IDENTIFIED BY hr123 QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE VIEW TO HR_PROD;
GRANT CONNECT, RESOURCE, CREATE VIEW TO HR_DEV;
-- Grant SYSTEM access to read these schemas for verification/agent work
GRANT SELECT ANY TABLE TO SYSTEM;
" "system" "OraclePassword123"

# 4. Create Base Objects (Identical in both initially)
# We use a subset of HR tables for simplicity but enough complexity
DDL_BASE="
    CREATE TABLE regions (
        region_id NUMBER CONSTRAINT region_id_nn NOT NULL,
        region_name VARCHAR2(25)
    );
    CREATE TABLE jobs (
        job_id VARCHAR2(10),
        job_title VARCHAR2(35) CONSTRAINT job_title_nn NOT NULL,
        min_salary NUMBER(6),
        max_salary NUMBER(6)
    );
    CREATE TABLE departments (
        department_id NUMBER(4),
        department_name VARCHAR2(30) CONSTRAINT dept_name_nn NOT NULL,
        manager_id NUMBER(6),
        location_id NUMBER(4)
    );
    CREATE TABLE employees (
        employee_id NUMBER(6),
        first_name VARCHAR2(20),
        last_name VARCHAR2(25) CONSTRAINT emp_last_name_nn NOT NULL,
        email VARCHAR2(25) CONSTRAINT emp_email_nn NOT NULL,
        phone_number VARCHAR2(20),
        hire_date DATE CONSTRAINT emp_hire_date_nn NOT NULL,
        job_id VARCHAR2(10) CONSTRAINT emp_job_nn NOT NULL,
        salary NUMBER(8,2),
        commission_pct NUMBER(2,2),
        manager_id NUMBER(6),
        department_id NUMBER(4)
    );
"

# Execute DDL in PROD
echo "Populating HR_PROD..."
oracle_query "$DDL_BASE" "HR_PROD" "hr123"

# Execute DDL in DEV
echo "Populating HR_DEV..."
oracle_query "$DDL_BASE" "HR_DEV" "hr123"

# 5. PLANT DRIFT ISSUES
echo "Planting schema drift issues..."

# Issue 1: Missing Table in DEV (REGIONS)
# Action: Drop REGIONS from DEV
oracle_query "DROP TABLE regions;" "HR_DEV" "hr123"

# Issue 2: Extra Table in DEV (FEATURE_FLAGS)
# Action: Create FEATURE_FLAGS in DEV
oracle_query "CREATE TABLE feature_flags (flag_key VARCHAR2(50), enabled CHAR(1));" "HR_DEV" "hr123"

# Issue 3: Data Type Mismatch (EMPLOYEES.SALARY)
# PROD: NUMBER(8,2) (Created in base)
# DEV: Change to NUMBER(12,2)
oracle_query "ALTER TABLE employees MODIFY salary NUMBER(12,2);" "HR_DEV" "hr123"

# Issue 4: Column Mismatch (DEPARTMENTS.COST_CENTER)
# PROD: Not present
# DEV: Add column
oracle_query "ALTER TABLE departments ADD cost_center VARCHAR2(20);" "HR_DEV" "hr123"

# Issue 5: Nullable Mismatch (JOBS.MIN_SALARY)
# Note: In base DDL, min_salary was created as nullable by default (no NOT NULL constraint).
# Let's make it NOT NULL in PROD, and keep it NULL in DEV.
oracle_query "ALTER TABLE jobs MODIFY min_salary NOT NULL;" "HR_PROD" "hr123"
# (DEV remains nullable)

# 6. Setup Anti-Gaming timestamps
date +%s > /tmp/task_start_time.txt
rm -f /home/ga/Desktop/drift_report.txt

echo "=== Setup Complete ==="
echo "PROD Schema: HR_PROD"
echo "DEV Schema:  HR_DEV"
echo "Drift issues planted."