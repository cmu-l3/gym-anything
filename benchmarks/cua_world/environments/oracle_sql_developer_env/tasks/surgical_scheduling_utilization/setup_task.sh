#!/bin/bash
echo "=== Setting up Surgical Scheduling & OR Utilization Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

# 1. Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# 2. Clean up previous artifacts
echo "Cleaning up previous schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER hosp_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# 3. Create HOSP_ADMIN user
echo "Creating HOSP_ADMIN schema..."
oracle_query "CREATE USER hosp_admin IDENTIFIED BY HospAdmin2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO hosp_admin;
GRANT RESOURCE TO hosp_admin;
GRANT CREATE VIEW TO hosp_admin;
GRANT CREATE PROCEDURE TO hosp_admin;
GRANT CREATE SESSION TO hosp_admin;
GRANT CREATE TABLE TO hosp_admin;
GRANT CREATE SEQUENCE TO hosp_admin;
EXIT;" "system"
echo "HOSP_ADMIN user created."

# 4. Create Tables and Insert Data
echo "Creating and populating SURGERY_SCHEDULE..."
sudo docker exec -i oracle-xe sqlplus -s hosp_admin/HospAdmin2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE SURGERY_SCHEDULE (
    schedule_id NUMBER PRIMARY KEY,
    room_id NUMBER NOT NULL,
    surgeon_id NUMBER NOT NULL,
    patient_id NUMBER NOT NULL,
    procedure_name VARCHAR2(200),
    start_time DATE NOT NULL,
    end_time DATE NOT NULL,
    status VARCHAR2(20) DEFAULT 'SCHEDULED'
);

CREATE SEQUENCE SEQ_SURGERY_SCHEDULE START WITH 1000 INCREMENT BY 1;

-- Clean record
INSERT INTO SURGERY_SCHEDULE VALUES (1, 1, 1, 101, 'Appendectomy', TO_DATE('2024-10-01 08:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 10:00', 'YYYY-MM-DD HH24:MI'), 'COMPLETED');
-- Overlaps S1 on ROOM (60 min overlap)
INSERT INTO SURGERY_SCHEDULE VALUES (2, 1, 2, 102, 'Cholecystectomy', TO_DATE('2024-10-01 09:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 11:00', 'YYYY-MM-DD HH24:MI'), 'COMPLETED');

-- Clean record
INSERT INTO SURGERY_SCHEDULE VALUES (3, 2, 3, 103, 'Hernia Repair', TO_DATE('2024-10-01 13:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 15:00', 'YYYY-MM-DD HH24:MI'), 'COMPLETED');
-- Overlaps S3 on SURGEON (30 min overlap)
INSERT INTO SURGERY_SCHEDULE VALUES (4, 3, 3, 104, 'Knee Arthroscopy', TO_DATE('2024-10-01 14:30', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 16:00', 'YYYY-MM-DD HH24:MI'), 'COMPLETED');

-- Cancelled record
INSERT INTO SURGERY_SCHEDULE VALUES (5, 4, 4, 105, 'Biopsy', TO_DATE('2024-10-01 18:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 19:00', 'YYYY-MM-DD HH24:MI'), 'CANCELLED');
-- Same time as S5, but no conflict because S5 is cancelled
INSERT INTO SURGERY_SCHEDULE VALUES (6, 4, 5, 106, 'Biopsy', TO_DATE('2024-10-01 18:30', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 19:30', 'YYYY-MM-DD HH24:MI'), 'COMPLETED');

-- Overlaps on BOTH Room and Surgeon (60 min overlap)
INSERT INTO SURGERY_SCHEDULE VALUES (7, 5, 6, 107, 'Cataract', TO_DATE('2024-10-02 08:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-02 09:30', 'YYYY-MM-DD HH24:MI'), 'COMPLETED');
INSERT INTO SURGERY_SCHEDULE VALUES (8, 5, 6, 108, 'Cataract 2', TO_DATE('2024-10-02 08:30', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-02 10:00', 'YYYY-MM-DD HH24:MI'), 'COMPLETED');

-- Non-overlapping sequential
INSERT INTO SURGERY_SCHEDULE VALUES (9, 6, 7, 109, 'Tonsillectomy', TO_DATE('2024-10-03 08:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-03 09:00', 'YYYY-MM-DD HH24:MI'), 'COMPLETED');
INSERT INTO SURGERY_SCHEDULE VALUES (10, 6, 7, 110, 'Tonsillectomy', TO_DATE('2024-10-03 09:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-03 10:00', 'YYYY-MM-DD HH24:MI'), 'COMPLETED');

COMMIT;
EXIT;
EOSQL
echo "Data populated."

# 5. Pre-configure SQL Developer connection
ensure_hr_connection "Hospital DB" "hosp_admin" "HospAdmin2024"

# 6. Ensure Oracle SQL Developer is maximized and focused
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="