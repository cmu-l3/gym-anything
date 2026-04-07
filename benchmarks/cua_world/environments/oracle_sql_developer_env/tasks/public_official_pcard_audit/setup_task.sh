#!/bin/bash
echo "=== Setting up Public Official P-Card Audit Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

# ---------------------------------------------------------------
# 1. Verify Oracle is running
# ---------------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# Wait for DB to be responsive
sleep 5

# ---------------------------------------------------------------
# 2. Clean up previous run artifacts
# ---------------------------------------------------------------
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER state_audit CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# 3. Create STATE_AUDIT schema
# ---------------------------------------------------------------
echo "Creating STATE_AUDIT schema..."
oracle_query "CREATE USER state_audit IDENTIFIED BY \"Audit2024!\"
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO state_audit;
GRANT RESOURCE TO state_audit;
GRANT CREATE VIEW TO state_audit;
GRANT CREATE MATERIALIZED VIEW TO state_audit;
GRANT CREATE SESSION TO state_audit;
GRANT CREATE TABLE TO state_audit;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create state_audit user"
    exit 1
fi
echo "state_audit user created."

# ---------------------------------------------------------------
# 4. Create Tables and Insert Seeded Data
# ---------------------------------------------------------------
echo "Creating tables and loading data..."

sudo docker exec -i oracle-xe sqlplus -s state_audit/\"Audit2024!\"@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- 1. AGENCIES
CREATE TABLE agencies (
    agency_id NUMBER PRIMARY KEY,
    agency_name VARCHAR2(100) NOT NULL,
    director_name VARCHAR2(100)
);

INSERT INTO agencies VALUES (1, 'Department of Transportation', 'Alice Director');
INSERT INTO agencies VALUES (2, 'Department of Education', 'Bob Superintendent');

-- 2. EMPLOYEES
CREATE TABLE employees (
    emp_id NUMBER PRIMARY KEY,
    agency_id NUMBER REFERENCES agencies(agency_id),
    first_name VARCHAR2(50),
    last_name VARCHAR2(50),
    title VARCHAR2(100),
    status VARCHAR2(20) DEFAULT 'ACTIVE'
);

INSERT INTO employees VALUES (101, 1, 'John', 'Doe', 'Inspector');
INSERT INTO employees VALUES (102, 1, 'Jane', 'Smith', 'Manager');
INSERT INTO employees VALUES (103, 2, 'Bob', 'Clark', 'Admin');
INSERT INTO employees VALUES (104, 2, 'Alice', 'Jones', 'Admin');
INSERT INTO employees VALUES (105, 2, 'Charlie', 'Brown', 'IT Staff');

-- 3. MERCHANT_CATEGORIES
CREATE TABLE merchant_categories (
    mcc_code VARCHAR2(10) PRIMARY KEY,
    description VARCHAR2(100),
    is_prohibited NUMBER(1) DEFAULT 0
);

INSERT INTO merchant_categories VALUES ('5111', 'Office Supplies', 0);
INSERT INTO merchant_categories VALUES ('5812', 'Restaurants', 0);
INSERT INTO merchant_categories VALUES ('4121', 'Taxicabs', 0);
INSERT INTO merchant_categories VALUES ('7995', 'Betting and Casino', 1);

-- 4. TRAVEL_AUTHORIZATIONS
CREATE TABLE travel_authorizations (
    auth_id NUMBER PRIMARY KEY,
    emp_id NUMBER REFERENCES employees(emp_id),
    start_date DATE,
    end_date DATE,
    destination VARCHAR2(100),
    purpose VARCHAR2(200),
    status VARCHAR2(20)
);

-- Valid travel for Jane (102) from Mar 15 to Mar 20, 2024
INSERT INTO travel_authorizations VALUES (1001, 102, TO_DATE('2024-03-15', 'YYYY-MM-DD'), TO_DATE('2024-03-20', 'YYYY-MM-DD'), 'Capital City', 'Conference', 'APPROVED');
-- Valid travel for John (101) from Mar 1 to Mar 5, 2024
INSERT INTO travel_authorizations VALUES (1002, 101, TO_DATE('2024-03-01', 'YYYY-MM-DD'), TO_DATE('2024-03-05', 'YYYY-MM-DD'), 'Site A', 'Inspection', 'APPROVED');

-- 5. EXPENSES
CREATE TABLE expenses (
    expense_id NUMBER PRIMARY KEY,
    emp_id NUMBER REFERENCES employees(emp_id),
    expense_date DATE,
    merchant_name VARCHAR2(100),
    mcc_code VARCHAR2(10) REFERENCES merchant_categories(mcc_code),
    amount NUMBER(10,2),
    description VARCHAR2(200)
);

-- VIOLATION 1: Split Transactions (emp 101, date 2024-03-01, sum=600, each<500)
INSERT INTO expenses VALUES (5001, 101, TO_DATE('2024-03-01', 'YYYY-MM-DD'), 'Office Supplies Co', '5111', 200, 'Supplies part 1');
INSERT INTO expenses VALUES (5002, 101, TO_DATE('2024-03-01', 'YYYY-MM-DD'), 'Office Supplies Co', '5111', 250, 'Supplies part 2');
INSERT INTO expenses VALUES (5003, 101, TO_DATE('2024-03-01', 'YYYY-MM-DD'), 'Office Supplies Co', '5111', 150, 'Supplies part 3');

-- VIOLATION 2: Unauthorized Weekend Spend (emp 102, date 2024-03-09 is Saturday, no travel auth covering this date)
INSERT INTO expenses VALUES (5004, 102, TO_DATE('2024-03-09', 'YYYY-MM-DD'), 'Fancy Steakhouse', '5812', 150, 'Dinner');

-- VIOLATION 3: Cross-Employee Duplicates (emps 103 and 104, exact same date, amount, merchant)
INSERT INTO expenses VALUES (5005, 103, TO_DATE('2024-03-15', 'YYYY-MM-DD'), 'City Cab', '4121', 85, 'Taxi ride');
INSERT INTO expenses VALUES (5006, 104, TO_DATE('2024-03-15', 'YYYY-MM-DD'), 'City Cab', '4121', 85, 'Taxi ride');

-- VIOLATION 4: Prohibited MCC (emp 105, 7995 is casino)
INSERT INTO expenses VALUES (5007, 105, TO_DATE('2024-03-20', 'YYYY-MM-DD'), 'Vegas Slots', '7995', 300, 'Entertainment');

-- Valid Transactions (Noise)
INSERT INTO expenses VALUES (5008, 101, TO_DATE('2024-03-02', 'YYYY-MM-DD'), 'Safe Hotel', '5812', 120, 'Lunch during travel');
INSERT INTO expenses VALUES (5009, 102, TO_DATE('2024-03-16', 'YYYY-MM-DD'), 'Conference Center', '5111', 400, 'Materials');
INSERT INTO expenses VALUES (5010, 103, TO_DATE('2024-03-10', 'YYYY-MM-DD'), 'Office Supplies Co', '5111', 450, 'Printer');
INSERT INTO expenses VALUES (5011, 104, TO_DATE('2024-03-11', 'YYYY-MM-DD'), 'Office Supplies Co', '5111', 480, 'Desks');

COMMIT;
EXIT;
EOSQL

echo "Data loaded."

# ---------------------------------------------------------------
# 5. Pre-configure SQL Developer connection
# ---------------------------------------------------------------
ensure_hr_connection "State Audit DB" "state_audit" "Audit2024!"

echo "Launching Oracle SQL Developer..."
# Launching occurs via the general env systemd service, but we will open the connection
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_start.png ga

echo "=== Task setup complete ==="