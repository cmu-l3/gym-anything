#!/bin/bash
# Setup script for Retail Fair Workweek Compliance Audit task
echo "=== Setting up Retail Fair Workweek Compliance Audit ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# --- Clean up and recreate the HR_COMPLIANCE user ---
echo "Setting up HR_COMPLIANCE schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER hr_compliance CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER hr_compliance IDENTIFIED BY Compliance2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO hr_compliance;
GRANT RESOURCE TO hr_compliance;
GRANT CREATE VIEW TO hr_compliance;
GRANT CREATE MATERIALIZED VIEW TO hr_compliance;
GRANT CREATE SESSION TO hr_compliance;
GRANT CREATE TABLE TO hr_compliance;
EXIT;" "system"

echo "HR_COMPLIANCE user created with required privileges"

# ============================================================
# CREATE TABLES
# ============================================================
echo "Creating schemas..."
sudo docker exec -i oracle-xe sqlplus -s hr_compliance/Compliance2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE employees (
    emp_id NUMBER PRIMARY KEY,
    first_name VARCHAR2(100),
    last_name VARCHAR2(100),
    store_id NUMBER,
    hourly_rate NUMBER(10,2),
    hire_date DATE,
    status VARCHAR2(20)
);

CREATE TABLE scheduled_shifts (
    schedule_id NUMBER PRIMARY KEY,
    emp_id NUMBER REFERENCES employees(emp_id),
    store_id NUMBER,
    planned_start_time DATE,
    planned_end_time DATE,
    published_time DATE,
    last_modified_time DATE
);

CREATE TABLE actual_shifts (
    shift_id NUMBER PRIMARY KEY,
    schedule_id NUMBER REFERENCES scheduled_shifts(schedule_id),
    emp_id NUMBER REFERENCES employees(emp_id),
    clock_in DATE,
    meal_out DATE,
    meal_in DATE,
    clock_out DATE
);

-- ============================================================
-- INSERT DETERMINISTIC SEED DATA
-- ============================================================

-- Emp 1 (Compliant) - Rate 15
INSERT INTO employees VALUES (1, 'Alice', 'Smith', 101, 15.00, SYSDATE-100, 'ACTIVE');
INSERT INTO scheduled_shifts VALUES (101, 1, 101, TO_DATE('2024-10-01 09:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 17:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-09-01 09:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-09-01 09:00','YYYY-MM-DD HH24:MI'));
INSERT INTO actual_shifts VALUES (1001, 101, 1, TO_DATE('2024-10-01 08:55','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 12:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 13:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 17:05','YYYY-MM-DD HH24:MI'));

-- Emp 2 (Clopening Violation) - Rate 20
INSERT INTO employees VALUES (2, 'Bob', 'Jones', 101, 20.00, SYSDATE-100, 'ACTIVE');
-- Shift 1 (Night)
INSERT INTO scheduled_shifts VALUES (102, 2, 101, TO_DATE('2024-10-01 15:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 23:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-09-01 09:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-09-01 09:00','YYYY-MM-DD HH24:MI'));
INSERT INTO actual_shifts VALUES (1002, 102, 2, TO_DATE('2024-10-01 14:55','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 19:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 19:30','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 23:30','YYYY-MM-DD HH24:MI'));
-- Shift 2 (Morning) - 6.5 hours rest (Violation: < 10)
INSERT INTO scheduled_shifts VALUES (103, 2, 101, TO_DATE('2024-10-02 06:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-02 14:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-09-01 09:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-09-01 09:00','YYYY-MM-DD HH24:MI'));
INSERT INTO actual_shifts VALUES (1003, 103, 2, TO_DATE('2024-10-02 06:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-02 10:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-02 10:30','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-02 14:00','YYYY-MM-DD HH24:MI'));

-- Emp 3 (Predictive Scheduling Violation) - Rate 25
INSERT INTO employees VALUES (3, 'Charlie', 'Brown', 101, 25.00, SYSDATE-100, 'ACTIVE');
-- Notice is 4 days (Violation: < 14)
INSERT INTO scheduled_shifts VALUES (104, 3, 101, TO_DATE('2024-10-05 09:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-05 17:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-09-01 09:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 09:00','YYYY-MM-DD HH24:MI'));
INSERT INTO actual_shifts VALUES (1004, 104, 3, TO_DATE('2024-10-05 08:55','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-05 12:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-05 12:45','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-05 17:00','YYYY-MM-DD HH24:MI'));

-- Emp 4 (Meal Break Violation) - Rate 18
INSERT INTO employees VALUES (4, 'Diana', 'Prince', 101, 18.00, SYSDATE-100, 'ACTIVE');
-- 8.5 hour shift, 20 min break (Violation: < 30)
INSERT INTO scheduled_shifts VALUES (105, 4, 101, TO_DATE('2024-10-10 09:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-10 17:30','YYYY-MM-DD HH24:MI'), TO_DATE('2024-09-01 09:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-09-01 09:00','YYYY-MM-DD HH24:MI'));
INSERT INTO actual_shifts VALUES (1005, 105, 4, TO_DATE('2024-10-10 09:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-10 12:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-10 12:20','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-10 17:30','YYYY-MM-DD HH24:MI'));
-- 8 hour shift, NULL meal breaks (Violation: Missing)
INSERT INTO scheduled_shifts VALUES (106, 4, 101, TO_DATE('2024-10-11 09:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-11 17:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-09-01 09:00','YYYY-MM-DD HH24:MI'), TO_DATE('2024-09-01 09:00','YYYY-MM-DD HH24:MI'));
INSERT INTO actual_shifts VALUES (1006, 106, 4, TO_DATE('2024-10-11 09:00','YYYY-MM-DD HH24:MI'), NULL, NULL, TO_DATE('2024-10-11 17:00','YYYY-MM-DD HH24:MI'));

COMMIT;
EXIT;
EOSQL
echo "Data seeding complete."

# Make sure export directory exists
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

# Pre-configure SQL Developer connection
ensure_hr_connection "HR Compliance" "hr_compliance" "Compliance2024"

# Launch SQL Developer and wait for it
echo "Ensuring SQL Developer is visible..."
if pgrep -x "java" > /dev/null && DISPLAY=:1 wmctrl -l | grep -qi "Oracle SQL Developer"; then
    echo "SQL Developer is running."
else
    # Not using standard launch here because container pre_start hook handles it, 
    # but we will just ensure it's maximized and focused.
    sleep 2
fi

# Open the connection so agent sees DB state
open_hr_connection_in_sqldeveloper

# Maximize SQL Developer
DISPLAY=:1 wmctrl -r "Oracle SQL Developer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Oracle SQL Developer" 2>/dev/null || true

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="