#!/bin/bash
# Setup script for Compensation Reconciliation Task
# Prepares the staging table and resets specific employee salaries to known starting states

set -e

echo "=== Setting up Compensation Reconciliation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# --- Pre-flight Check ---
echo "[1/4] Checking Database Connectivity..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

wait_for_oracle 300 || exit 1

# --- Clean Slate & Data Prep ---
echo "[2/4] preparing staging data..."

# We use a Python script to handle the SQL logic cleanly
python3 << 'PYEOF'
import oracledb
import sys

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Clean up potential previous run artifacts
    try:
        cursor.execute("DROP TABLE market_salary_survey CASCADE CONSTRAINTS")
    except oracledb.DatabaseError:
        pass
    
    try:
        cursor.execute("DROP TABLE salary_change_log CASCADE CONSTRAINTS")
    except oracledb.DatabaseError:
        pass
        
    try:
        cursor.execute("DROP SEQUENCE salary_log_seq")
    except oracledb.DatabaseError:
        pass

    # 2. Reset specific employee salaries to known baselines (Group A & B)
    # Group A (To be updated):
    cursor.execute("UPDATE employees SET salary=4800 WHERE employee_id=105")
    cursor.execute("UPDATE employees SET salary=4800 WHERE employee_id=106")
    cursor.execute("UPDATE employees SET salary=4200 WHERE employee_id=107")
    cursor.execute("UPDATE employees SET salary=3100 WHERE employee_id=115")
    cursor.execute("UPDATE employees SET salary=2900 WHERE employee_id=116")
    cursor.execute("UPDATE employees SET salary=2800 WHERE employee_id=117")
    cursor.execute("UPDATE employees SET salary=2500 WHERE employee_id=119")
    cursor.execute("UPDATE employees SET salary=3200 WHERE employee_id=125")
    cursor.execute("UPDATE employees SET salary=2700 WHERE employee_id=126")
    cursor.execute("UPDATE employees SET salary=2400 WHERE employee_id=127")
    cursor.execute("UPDATE employees SET salary=2500 WHERE employee_id=131")
    cursor.execute("UPDATE employees SET salary=2100 WHERE employee_id=132")
    cursor.execute("UPDATE employees SET salary=2200 WHERE employee_id=136")
    cursor.execute("UPDATE employees SET salary=2500 WHERE employee_id=140")
    cursor.execute("UPDATE employees SET salary=2500 WHERE employee_id=144")
    
    # Group B (No change expected):
    cursor.execute("UPDATE employees SET salary=24000 WHERE employee_id=100")
    cursor.execute("UPDATE employees SET salary=17000 WHERE employee_id=101")
    cursor.execute("UPDATE employees SET salary=17000 WHERE employee_id=102")
    cursor.execute("UPDATE employees SET salary=9000 WHERE employee_id=103")
    cursor.execute("UPDATE employees SET salary=6000 WHERE employee_id=104")
    cursor.execute("UPDATE employees SET salary=12008 WHERE employee_id=108")
    cursor.execute("UPDATE employees SET salary=9000 WHERE employee_id=109")
    
    # Clean up any Group C inserts from previous runs (New employees)
    cursor.execute("DELETE FROM employees WHERE email IN ('MORRISON', 'TANAKA', 'BEAUMONT', 'ASANTE', 'VOLKOV', 'RICCI', 'PATEL', 'REINHARDT')")
    
    conn.commit()

    # 3. Create and Populate Staging Table
    cursor.execute("""
        CREATE TABLE market_salary_survey (
            survey_id NUMBER PRIMARY KEY,
            employee_id NUMBER,
            job_id VARCHAR2(10),
            market_first_name VARCHAR2(20),
            market_last_name VARCHAR2(25),
            market_salary NUMBER(8,2),
            survey_date DATE DEFAULT SYSDATE,
            region VARCHAR2(30)
        )
    """)

    # Data to insert
    # Group A: Matched, Low Salary -> Needs Update (15 rows)
    data_a = [
        (1, 105, 'IT_PROG', 'David', 'Austin', 6000),
        (2, 106, 'IT_PROG', 'Valli', 'Pataballa', 5800),
        (3, 107, 'IT_PROG', 'Diana', 'Lorentz', 5200),
        (4, 115, 'PU_CLERK', 'Alexander', 'Khoo', 3800),
        (5, 116, 'PU_CLERK', 'Shelli', 'Baida', 3600),
        (6, 117, 'PU_CLERK', 'Sigal', 'Tobias', 3500),
        (7, 119, 'PU_CLERK', 'Karen', 'Colmenares', 3200),
        (8, 125, 'ST_CLERK', 'Julia', 'Nayer', 4000),
        (9, 126, 'ST_CLERK', 'Irene', 'Mikkilineni', 3400),
        (10, 127, 'ST_CLERK', 'James', 'Landry', 3100),
        (11, 131, 'ST_CLERK', 'James', 'Marlow', 3200),
        (12, 132, 'ST_CLERK', 'TJ', 'Olson', 2700),
        (13, 136, 'ST_CLERK', 'Hazel', 'Philtanker', 2800),
        (14, 140, 'ST_CLERK', 'Joshua', 'Patel', 3200),
        (15, 144, 'ST_CLERK', 'Peter', 'Vargas', 3100)
    ]
    
    # Group B: Matched, OK Salary -> No Update (17 rows)
    data_b = [
        (16, 100, 'AD_PRES', 'Steven', 'King', 25000),
        (17, 101, 'AD_VP', 'Neena', 'Kochhar', 17500),
        (18, 102, 'AD_VP', 'Lex', 'De Haan', 17200),
        (19, 103, 'IT_PROG', 'Alexander', 'Hunold', 9500),
        (20, 104, 'IT_PROG', 'Bruce', 'Ernst', 6400),
        (21, 108, 'FI_MGR', 'Nancy', 'Greenberg', 12500),
        (22, 109, 'FI_ACCOUNT', 'Daniel', 'Faviet', 9200),
        (23, 110, 'FI_ACCOUNT', 'John', 'Chen', 8800),
        (24, 111, 'FI_ACCOUNT', 'Ismael', 'Sciarra', 8000),
        (25, 112, 'FI_ACCOUNT', 'Jose Manuel', 'Urman', 8100),
        (26, 113, 'FI_ACCOUNT', 'Luis', 'Popp', 7200),
        (27, 114, 'PU_MAN', 'Den', 'Raphaely', 11800),
        (28, 120, 'ST_MAN', 'Matthew', 'Weiss', 8600),
        (29, 121, 'ST_MAN', 'Adam', 'Fripp', 8800),
        (30, 122, 'ST_MAN', 'Payam', 'Kaufling', 8400),
        (31, 123, 'ST_MAN', 'Shanta', 'Vollman', 7000),
        (32, 124, 'ST_MAN', 'Kevin', 'Mourgos', 6200)
    ]
    
    # Group C: Not Matched -> Needs Insert (8 rows)
    data_c = [
        (33, None, 'IT_PROG', 'Rachel', 'Morrison', 7500),
        (34, None, 'SA_REP', 'Derek', 'Tanaka', 8200),
        (35, None, 'FI_ACCOUNT', 'Simone', 'Beaumont', 7800),
        (36, None, 'ST_CLERK', 'Kwame', 'Asante', 3500),
        (37, None, 'PU_CLERK', 'Lena', 'Volkov', 3300),
        (38, None, 'SA_REP', 'Marco', 'Ricci', 9100),
        (39, None, 'IT_PROG', 'Anika', 'Patel', 8800),
        (40, None, 'HR_REP', 'Tobias', 'Reinhardt', 6800)
    ]

    sql = "INSERT INTO market_salary_survey (survey_id, employee_id, job_id, market_first_name, market_last_name, market_salary, region) VALUES (:1, :2, :3, :4, :5, :6, 'North America')"
    
    cursor.executemany(sql, data_a + data_b + data_c)
    conn.commit()
    print(f"Staging table created with {len(data_a) + len(data_b) + len(data_c)} records.")

except Exception as e:
    print(f"Database setup failed: {e}")
    sys.exit(1)
finally:
    if 'conn' in locals(): conn.close()
PYEOF

echo "[3/4] Resetting UI state..."
# Close any existing DBeaver windows to ensure clean start
pkill -f dbeaver 2>/dev/null || true

# Ensure DBeaver is installed (should be from environment, but safe check)
if ! which dbeaver-ce >/dev/null; then
    echo "Warning: DBeaver not found, ensuring terminal is ready."
fi

# Create a sample report file to indicate where to save it (optional, but helpful)
touch /home/ga/Desktop/reconciliation_report.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "[4/4] Task Setup Complete."