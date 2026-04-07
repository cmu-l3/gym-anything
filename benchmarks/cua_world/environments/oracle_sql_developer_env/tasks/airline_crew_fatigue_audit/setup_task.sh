#!/bin/bash
echo "=== Setting up Airline Crew Fatigue Audit Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# ---------------------------------------------------------------
# 1. Verify Oracle is running
# ---------------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# ---------------------------------------------------------------
# 2. Clean up previous run artifacts
# ---------------------------------------------------------------
echo "Cleaning up previous schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER aviation_audit CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

rm -f /home/ga/Documents/faa_audit_report.csv 2>/dev/null || true

# ---------------------------------------------------------------
# 3. Create AVIATION_AUDIT schema
# ---------------------------------------------------------------
echo "Creating AVIATION_AUDIT schema..."
oracle_query "CREATE USER aviation_audit IDENTIFIED BY Flight2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO aviation_audit;
GRANT RESOURCE TO aviation_audit;
GRANT CREATE VIEW TO aviation_audit;
GRANT CREATE PROCEDURE TO aviation_audit;
GRANT CREATE SESSION TO aviation_audit;
GRANT CREATE TABLE TO aviation_audit;
GRANT CREATE SEQUENCE TO aviation_audit;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create aviation_audit user"
    exit 1
fi
echo "User created."

# ---------------------------------------------------------------
# 4. Create tables and load data
# ---------------------------------------------------------------
echo "Creating tables and loading flight data..."

sudo docker exec -i oracle-xe sqlplus -s aviation_audit/Flight2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE crew_members (
    crew_id       NUMBER PRIMARY KEY,
    first_name    VARCHAR2(50),
    last_name     VARCHAR2(50),
    base_airport  VARCHAR2(10),
    position      VARCHAR2(20),
    hire_date     DATE
);

CREATE TABLE flights (
    flight_id     NUMBER PRIMARY KEY,
    carrier       VARCHAR2(5),
    flight_num    VARCHAR2(10),
    origin        VARCHAR2(10),
    dest          VARCHAR2(10),
    flight_date   DATE,
    sched_dep     DATE,
    actual_dep    DATE,
    sched_arr     DATE,
    actual_arr    DATE,
    tail_number   VARCHAR2(20)
);

CREATE TABLE crew_roster (
    roster_id      NUMBER PRIMARY KEY,
    crew_id        NUMBER REFERENCES crew_members(crew_id),
    flight_id      NUMBER REFERENCES flights(flight_id),
    check_in_time  DATE,
    check_out_time DATE,
    status         VARCHAR2(20)
);

CREATE SEQUENCE violation_seq START WITH 1 INCREMENT BY 1;

-- Seed Data PL/SQL Block
DECLARE
   v_date DATE;
BEGIN
   -- Insert Crew
   INSERT INTO crew_members VALUES (101, 'John', 'Doe', 'ORD', 'CPT', SYSDATE-1000);
   INSERT INTO crew_members VALUES (102, 'Jane', 'Smith', 'DFW', 'FO', SYSDATE-500);
   INSERT INTO crew_members VALUES (103, 'Bob', 'Johnson', 'MIA', 'CPT', SYSDATE-2000);

   -- Crew 101: Insufficient Rest Violation (< 10 hours)
   -- Flight 1: Ends Jan 1, 14:00 (Check-out 14:30)
   v_date := TO_DATE('2024-01-01 10:00:00', 'YYYY-MM-DD HH24:MI:SS');
   INSERT INTO flights VALUES (1001, 'AA', '100', 'ORD', 'JFK', TRUNC(v_date), v_date, v_date, v_date+4/24, v_date+4/24, 'N101AA');
   INSERT INTO crew_roster VALUES (1, 101, 1001, v_date-1/24, v_date+4.5/24, 'COMPLETED');
   
   -- Flight 2: Starts Jan 1, 23:00 (Check-in 22:00) 
   -- Rest time = 22:00 - 14:30 = 7.5 hours (< 10) -> VIOLATION
   v_date := TO_DATE('2024-01-01 23:00:00', 'YYYY-MM-DD HH24:MI:SS');
   INSERT INTO flights VALUES (1002, 'AA', '101', 'JFK', 'ORD', TRUNC(v_date), v_date, v_date, v_date+4/24, v_date+4/24, 'N101AA');
   INSERT INTO crew_roster VALUES (2, 101, 1002, v_date-1/24, v_date+4.5/24, 'COMPLETED');

   -- Flight 3: Starts Jan 3, legal rest
   v_date := TO_DATE('2024-01-03 10:00:00', 'YYYY-MM-DD HH24:MI:SS');
   INSERT INTO flights VALUES (1003, 'AA', '102', 'ORD', 'MIA', TRUNC(v_date), v_date, v_date, v_date+4/24, v_date+4/24, 'N101AA');
   INSERT INTO crew_roster VALUES (3, 101, 1003, v_date-1/24, v_date+4.5/24, 'COMPLETED');

   -- Crew 102: Exceeded 28-Day Limit (> 100 hours)
   -- 12 flights of 9 hours each = 108 hours. 1 flight every 2 days.
   v_date := TO_DATE('2024-01-01 10:00:00', 'YYYY-MM-DD HH24:MI:SS');
   FOR i IN 1..12 LOOP
      INSERT INTO flights VALUES (2000+i, 'AA', TO_CHAR(200+i), 'DFW', 'LHR', TRUNC(v_date), v_date, v_date, v_date+9/24, v_date+9/24, 'N102AA');
      INSERT INTO crew_roster VALUES (10+i, 102, 2000+i, v_date-1/24, v_date+9.5/24, 'COMPLETED');
      v_date := v_date + 2; -- Step forward 2 days
   END LOOP;

   -- Crew 103: Completely Legal
   v_date := TO_DATE('2024-01-05 10:00:00', 'YYYY-MM-DD HH24:MI:SS');
   INSERT INTO flights VALUES (3001, 'AA', '300', 'MIA', 'ORD', TRUNC(v_date), v_date, v_date, v_date+3/24, v_date+3/24, 'N103AA');
   INSERT INTO crew_roster VALUES (31, 103, 3001, v_date-1/24, v_date+3.5/24, 'COMPLETED');

   COMMIT;
END;
/
EXIT;
EOSQL
echo "Data loaded successfully."

# ---------------------------------------------------------------
# 5. Pre-configure SQL Developer Connection
# ---------------------------------------------------------------
echo "Configuring SQL Developer connection..."
ensure_hr_connection "Aviation Audit DB" "aviation_audit" "Flight2024"

# ---------------------------------------------------------------
# 6. Launch and setup UI
# ---------------------------------------------------------------
echo "Checking SQL Developer..."
if ! pgrep -f "sqldeveloper" > /dev/null; then
    echo "Starting SQL Developer..."
    su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 /opt/sqldeveloper/sqldeveloper.sh > /tmp/sqldeveloper.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "oracle sql developer"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "oracle sql developer" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="