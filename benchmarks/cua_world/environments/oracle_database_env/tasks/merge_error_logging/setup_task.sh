#!/bin/bash
# Setup for merge_error_logging task
# Creates staging table with dirty data and adds constraints to target table

set -e

echo "=== Setting up Merge Error Logging Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Wait for HR schema ---
echo "[2/4] Verifying HR schema connectivity..."
for attempt in {1..5}; do
    if oracle_query_raw "SELECT 1 FROM DUAL;" "hr" > /dev/null 2>&1; then
        echo "  HR schema connected."
        break
    fi
    echo "  Waiting for DB..."
    sleep 5
done

# --- Setup Data Environment ---
echo "[3/4] Resetting data state..."

# We use a Python script inside the setup to handle the complex data setup reliably
python3 << 'PYEOF'
import oracledb
import sys

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Clean up target table (EMPLOYEES) to standard state
    # First, drop any artifacts from previous runs
    try: cursor.execute("DROP TABLE err_employees_log PURGE")
    except: pass
    try: cursor.execute("DROP TABLE employee_updates PURGE")
    except: pass
    
    # Reload standard HR data if counts look wrong (simple heuristic)
    cursor.execute("SELECT COUNT(*) FROM employees")
    count = cursor.fetchone()[0]
    if count != 107:
        print("WARNING: Employee count is not 107. Resetting is recommended but skipping for speed if close.")

    # 2. Add specific Check Constraint for the scenario
    # "Salary must be positive" - this will trigger one of our errors
    try:
        cursor.execute("ALTER TABLE employees DROP CONSTRAINT chk_salary_min")
    except:
        pass
    cursor.execute("ALTER TABLE employees ADD CONSTRAINT chk_salary_min CHECK (salary > 0)")

    # 3. Create Staging Table (EMPLOYEE_UPDATES)
    # It mimics EMPLOYEES structure
    cursor.execute("""
        CREATE TABLE employee_updates AS 
        SELECT * FROM employees WHERE 1=0
    """)
    
    # 4. Populate Staging Table with Scenario Data
    # 3 Valid Updates, 2 Valid Inserts, 5 Errors
    
    data = [
        # --- VALID UPDATES (IDs exist in EMPLOYEES) ---
        # 100: King (Valid update)
        (100, 'Steven', 'King', 'SKING', '515.123.4567', '17-JUN-03', 'AD_PRES', 25000, 0.1, 100, 90),
        # 103: Hunold (Valid update)
        (103, 'Alexander', 'Hunold', 'AHUNOLD', '590.423.4567', '03-JAN-06', 'IT_PROG', 9500, 0.2, 102, 60),
        # 104: Ernst (Valid update)
        (104, 'Bruce', 'Ernst', 'BERNST', '590.423.4568', '21-MAY-07', 'IT_PROG', 6000, 0.3, 103, 60),

        # --- VALID INSERTS (IDs do not exist) ---
        # 301: Valid New Hire
        (301, 'Valid', 'HireA', 'VHIREA', '555.000.0001', '01-JAN-24', 'IT_PROG', 5000, None, 103, 60),
        # 302: Valid New Hire
        (302, 'Valid', 'HireB', 'VHIREB', '555.000.0002', '01-JAN-24', 'SA_REP', 7000, 0.1, 145, 80),

        # --- ERRORS (To be caught by LOG ERRORS) ---
        # 101: Kochhar (Check Constraint: Negative Salary) - Update attempt
        (101, 'Neena', 'Kochhar', 'NKOCHHAR', '515.123.4568', '21-SEP-05', 'AD_VP', -5000, None, 100, 90),
        
        # 303: Bad Job ID (FK Constraint) - Insert attempt
        (303, 'Bad', 'Job', 'BADJOB', '555.000.0003', '01-JAN-24', 'INVALID_JOB', 5000, None, 103, 60),
        
        # 304: Bad Dept ID (FK Constraint) - Insert attempt
        (304, 'Bad', 'Dept', 'BADDEPT', '555.000.0004', '01-JAN-24', 'IT_PROG', 5000, None, 103, 9999),
        
        # 305: Duplicate Email (Unique Constraint) - Insert attempt
        # 'SKING' already belongs to emp 100
        (305, 'Copy', 'Cat', 'SKING', '555.000.0005', '01-JAN-24', 'IT_PROG', 5000, None, 103, 60),

        # 102: De Haan (Unique Constraint on Update) - Update attempt
        # Trying to update 102's email to AHUNOLD (which belongs to 103)
        (102, 'Lex', 'De Haan', 'AHUNOLD', '515.123.4569', '13-JAN-01', 'AD_VP', 17000, None, 100, 90)
    ]
    
    cursor.executemany("""
        INSERT INTO employee_updates 
        (employee_id, first_name, last_name, email, phone_number, hire_date, job_id, salary, commission_pct, manager_id, department_id)
        VALUES (:1, :2, :3, :4, :5, TO_DATE(:6, 'DD-MON-YY'), :7, :8, :9, :10, :11)
    """, data)
    
    conn.commit()
    print(f"Staging table created with {len(data)} rows.")
    conn.close()

except Exception as e:
    print(f"Error setting up data: {e}")
    sys.exit(1)
PYEOF

# --- Capture Initial State ---
echo "[4/4] Recording initial state..."
oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" | tr -d ' ' > /tmp/initial_emp_count.txt
date +%s > /tmp/task_start_time.txt
# Remove the report file if it exists
rm -f /home/ga/Desktop/sync_errors.csv

# Ensure SQL Developer/DBeaver is handy in menus or just let agent use terminal
# We don't force-launch a tool, but we ensure the environment is clean.

echo "=== Setup Complete ==="