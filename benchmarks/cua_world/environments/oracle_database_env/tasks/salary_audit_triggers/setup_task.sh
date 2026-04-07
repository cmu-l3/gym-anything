#!/bin/bash
# Setup script for Salary Audit Triggers task
# Ensures clean state by removing any existing audit objects and resetting specific employee data.

set -e
echo "=== Setting up Salary Audit Triggers Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# --- 1. Verify Database Connection ---
echo "Verifying Oracle connection..."
if ! oracle_query "SELECT 1 FROM DUAL;" "hr" > /dev/null; then
    echo "ERROR: Cannot connect to HR schema."
    exit 1
fi

# --- 2. Clean up Previous Artifacts ---
# We drop objects if they exist to ensure the agent starts from a blank slate
echo "Cleaning up previous objects..."
oracle_query "
BEGIN
    BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE audit_seq'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE salary_audit_log CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TRIGGER trg_salary_audit'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TRIGGER trg_prevent_manager_delete'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/" "hr" > /dev/null 2>&1 || true

# --- 3. Reset Test Employee Data ---
# Ensure employees involved in the test are in their original state
# Emp 200: Jennifer Whalen, AD_ASST, Sal 4400, Dept 10
# Emp 105: David Austin, IT_PROG, Dept 60
# Emp 206: William Gietz, AC_ACCOUNT
# Emp 100: Steven King (Manager) - Ensure he exists
echo "Resetting test data..."
oracle_query "
BEGIN
    UPDATE employees SET salary = 4400, job_id = 'AD_ASST', department_id = 10 WHERE employee_id = 200;
    UPDATE employees SET department_id = 60 WHERE employee_id = 105;
    UPDATE employees SET job_id = 'AC_ACCOUNT' WHERE employee_id = 206;
    
    -- Ensure Steven King exists (in case previous run deleted him by mistake)
    -- We assume standard HR schema, but if he's gone, we can't easily recreate due to FKs. 
    -- HR schema is usually persistent/read-only in this env, but we check just in case.
    NULL; 
    COMMIT;
END;
/" "hr"

# --- 4. Setup Environment ---
# Ensure DBeaver is running/available (optional but helpful context)
if ! pgrep -f dbeaver > /dev/null; then
    echo "DBeaver not running (optional)."
fi

# Remove previous output file
rm -f /home/ga/Desktop/audit_log.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Objects dropped. Test data reset."