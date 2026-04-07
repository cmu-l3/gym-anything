#!/bin/bash
echo "=== Setting up Aviation Safety Text Mining Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# 1. Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

# 2. Clean up previous run artifacts
echo "Cleaning up previous run artifacts..."
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
BEGIN
  EXECUTE IMMEDIATE 'DROP USER aviation CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  CTXSYS.CTX_DDL.DROP_STOPLIST('ASRS_STOPLIST');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;
EOSQL

sleep 2

# 3. Create AVIATION schema and grant necessary Oracle Text privileges
echo "Creating AVIATION schema..."
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
CREATE USER aviation IDENTIFIED BY "Aviation2024"
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;

GRANT CONNECT, RESOURCE TO aviation;
GRANT CREATE VIEW TO aviation;
GRANT CREATE MATERIALIZED VIEW TO aviation;
GRANT CREATE PROCEDURE TO aviation;
GRANT CREATE SESSION TO aviation;
GRANT CREATE TABLE TO aviation;

-- Crucial privileges for Oracle Text
GRANT CTXAPP TO aviation;
GRANT EXECUTE ON CTXSYS.CTX_DDL TO aviation;
EXIT;
EOSQL

# 4. Create ASRS_REPORTS table and populate with highly realistic synthetic data
echo "Populating ASRS reports data..."
sudo docker exec -i oracle-xe sqlplus -s aviation/Aviation2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE asrs_reports (
    report_id      NUMBER PRIMARY KEY,
    event_date     DATE,
    location_id    VARCHAR2(10),
    aircraft_type  VARCHAR2(50),
    narrative      CLOB
);

INSERT INTO asrs_reports VALUES (1001, SYSDATE-10, 'SFO', 'B737', 
'On approach to SFO at 10,000 FT, the FO noticed a bright green laser illumination from the 11 o clock position. It hit the flight deck multiple times. No injuries reported. The AIRCRAFT continued normal FLIGHT to the RUNWAY.');

INSERT INTO asrs_reports VALUES (1002, SYSDATE-15, 'JFK', 'A320', 
'Climbing through FL180, we spotted a small quadcopter drone passing approx 500 FEET below us. ATC was notified immediately. Evasive action was not required. Normal FLIGHT resumed.');

INSERT INTO asrs_reports VALUES (1003, SYSDATE-20, 'ORD', 'B777', 
'Smooth flight at FL350. Passenger experienced medical issue. Diverted to DEN. Landed safely on the RUNWAY.');

INSERT INTO asrs_reports VALUES (1004, SYSDATE-25, 'LAX', 'C172', 
'Operating in VFR pattern at 1500 FT. Another AIRCRAFT cut in front of us. Evasive action taken to avoid collision.');

INSERT INTO asrs_reports VALUES (1005, SYSDATE-30, 'MIA', 'B757', 
'Laser strike at 4,000 FT during departure. Pilot vision temporarily obscured by intense green illumination. Handed control to First Officer.');

INSERT INTO asrs_reports VALUES (1006, SYSDATE-35, 'SEA', 'DH8', 
'UAV/Drone spotted 2 miles from runway threshold at 800 FEET. Appeared to be DJI model hovering directly in the glide path.');

INSERT INTO asrs_reports VALUES (1007, SYSDATE-40, 'DFW', 'A321', 
'Cruising at FL310. Severe turbulence encountered unexpectedly. Seatbelt sign illuminated. Several passengers bumped heads.');

COMMIT;
EXIT;
EOSQL

# 5. Pre-configure the SQL Developer connection for the agent
ensure_hr_connection "Aviation DB" "aviation" "Aviation2024"

# 6. Maximize and focus SQL Developer window
sleep 3
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task Setup Complete ==="