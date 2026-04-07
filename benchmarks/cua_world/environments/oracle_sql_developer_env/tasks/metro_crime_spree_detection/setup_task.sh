#!/bin/bash
# Setup script for Metropolitan Crime Spree Detection task
echo "=== Setting up Metropolitan Crime Spree Detection Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents

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
echo "Cleaning up previous run artifacts..."

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER crime_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# 3. Create CRIME_ANALYST schema
# ---------------------------------------------------------------
echo "Creating CRIME_ANALYST schema..."

oracle_query "CREATE USER crime_analyst IDENTIFIED BY Crime2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO crime_analyst;
GRANT RESOURCE TO crime_analyst;
GRANT CREATE VIEW TO crime_analyst;
GRANT CREATE SESSION TO crime_analyst;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create crime_analyst user"
    exit 1
fi

# ---------------------------------------------------------------
# 4. Create schema tables
# ---------------------------------------------------------------
echo "Creating schema tables..."

sudo docker exec -i oracle-xe sqlplus -s crime_analyst/Crime2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE precincts (
    precinct_id    NUMBER PRIMARY KEY,
    precinct_name  VARCHAR2(100) NOT NULL,
    division       VARCHAR2(50),
    sq_miles       NUMBER(5,2)
);

CREATE TABLE beats (
    beat_id        NUMBER PRIMARY KEY,
    precinct_id    NUMBER REFERENCES precincts(precinct_id),
    police_beat    VARCHAR2(20) NOT NULL,
    neighborhood   VARCHAR2(100)
);

CREATE TABLE incidents (
    incident_id        NUMBER PRIMARY KEY,
    beat_id            NUMBER REFERENCES beats(beat_id),
    crime_category     VARCHAR2(50) NOT NULL,
    crime_description  VARCHAR2(200),
    incident_timestamp TIMESTAMP NOT NULL,
    priority_level     NUMBER,
    status             VARCHAR2(20),
    location_type      VARCHAR2(50)
);

CREATE TABLE dispatches (
    dispatch_id        NUMBER PRIMARY KEY,
    incident_id        NUMBER REFERENCES incidents(incident_id),
    unit_id            VARCHAR2(20),
    call_timestamp     TIMESTAMP,
    dispatch_timestamp TIMESTAMP,
    arrival_timestamp  TIMESTAMP,
    clear_timestamp    TIMESTAMP
);

CREATE TABLE arrests (
    arrest_id          NUMBER PRIMARY KEY,
    incident_id        NUMBER REFERENCES incidents(incident_id),
    offender_id        NUMBER,
    arrest_timestamp   TIMESTAMP,
    charge_code        VARCHAR2(50)
);

CREATE SEQUENCE incident_seq START WITH 10000 INCREMENT BY 1;
CREATE SEQUENCE dispatch_seq START WITH 50000 INCREMENT BY 1;

EXIT;
EOSQL
echo "  Tables created."

# ---------------------------------------------------------------
# 5. Insert realistic data
# ---------------------------------------------------------------
echo "Populating data..."
sudo docker exec -i oracle-xe sqlplus -s crime_analyst/Crime2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

BEGIN
    -- Base geographic data
    INSERT INTO precincts VALUES (1, 'Central', 'Metro', 5.2);
    INSERT INTO precincts VALUES (2, 'Northside', 'Metro', 8.4);
    INSERT INTO precincts VALUES (3, 'Southside', 'Metro', 10.1);

    INSERT INTO beats VALUES (101, 1, 'B-101', 'Downtown Core');
    INSERT INTO beats VALUES (102, 1, 'B-102', 'River North');
    INSERT INTO beats VALUES (201, 2, 'B-201', 'Uptown');
    INSERT INTO beats VALUES (301, 3, 'B-301', 'Hyde Park');
    
    -- Generate randomized incidents for PIVOT and SLA
    FOR i IN 1..250 LOOP
        DECLARE
            v_beat NUMBER;
            v_cat VARCHAR2(50);
            v_pri NUMBER;
            v_inc_time TIMESTAMP;
            v_inc_id NUMBER;
            v_resp_mins NUMBER;
        BEGIN
            v_beat := CASE MOD(i, 4) WHEN 0 THEN 101 WHEN 1 THEN 102 WHEN 2 THEN 201 ELSE 301 END;
            v_cat := CASE MOD(i, 6)
                WHEN 0 THEN 'THEFT'
                WHEN 1 THEN 'BURGLARY'
                WHEN 2 THEN 'ASSAULT'
                WHEN 3 THEN 'MOTOR_VEHICLE_THEFT'
                WHEN 4 THEN 'ROBBERY'
                ELSE 'HOMICIDE'
            END;
            v_pri := CASE WHEN v_cat IN ('HOMICIDE', 'ROBBERY', 'ASSAULT') THEN 1 ELSE 2 END;
            v_inc_time := TIMESTAMP '2024-01-01 00:00:00' + numtodsinterval(MOD(i * 137, 365*24), 'hour');
            
            SELECT incident_seq.NEXTVAL INTO v_inc_id FROM dual;
            
            INSERT INTO incidents VALUES (v_inc_id, v_beat, v_cat, 'Routine generation', v_inc_time, v_pri, 'CLOSED', 'STREET');
            
            -- Dispatch Data
            v_resp_mins := CASE v_pri WHEN 1 THEN 5 + MOD(i, 15) ELSE 15 + MOD(i, 45) END;
            INSERT INTO dispatches VALUES (
                dispatch_seq.NEXTVAL, v_inc_id, 'UNIT-'||MOD(i,10),
                v_inc_time,
                v_inc_time + numtodsinterval(2, 'minute'),
                v_inc_time + numtodsinterval(v_resp_mins, 'minute'),
                v_inc_time + numtodsinterval(60, 'minute')
            );
        END;
    END LOOP;

    -- Inject specifically crafted Spree 1: 4 BURGLARY in Beat 101 within 72 hours
    -- Dates: May 10 08:00, May 11 12:00, May 12 16:00, May 13 06:00 (All within 72h of May 13)
    INSERT INTO incidents VALUES (1001, 101, 'BURGLARY', 'Spree 1A', TIMESTAMP '2024-05-10 08:00:00', 2, 'OPEN', 'RESIDENCE');
    INSERT INTO incidents VALUES (1002, 101, 'BURGLARY', 'Spree 1B', TIMESTAMP '2024-05-11 12:00:00', 2, 'OPEN', 'RESIDENCE');
    INSERT INTO incidents VALUES (1003, 101, 'BURGLARY', 'Spree 1C', TIMESTAMP '2024-05-12 16:00:00', 2, 'OPEN', 'RESIDENCE');
    INSERT INTO incidents VALUES (1004, 101, 'BURGLARY', 'Spree 1D', TIMESTAMP '2024-05-13 06:00:00', 2, 'OPEN', 'RESIDENCE');

    -- Inject Spree 2: 3 THEFT in Beat 201 within 48 hours
    INSERT INTO incidents VALUES (2001, 201, 'THEFT', 'Spree 2A', TIMESTAMP '2024-06-01 10:00:00', 3, 'OPEN', 'STREET');
    INSERT INTO incidents VALUES (2002, 201, 'THEFT', 'Spree 2B', TIMESTAMP '2024-06-02 11:00:00', 3, 'OPEN', 'STREET');
    INSERT INTO incidents VALUES (2003, 201, 'THEFT', 'Spree 2C', TIMESTAMP '2024-06-03 09:00:00', 3, 'OPEN', 'STREET');

    COMMIT;
END;
/
EXIT;
EOSQL
echo "  Data populated."

# ---------------------------------------------------------------
# 6. Pre-configure SQL Developer connection
# ---------------------------------------------------------------
ensure_hr_connection "CRIME Database" "crime_analyst" "Crime2024"

# Open SQL developer connection in GUI if running
open_hr_connection_in_sqldeveloper 2>/dev/null || true

# Wait a moment for UI to stabilize
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task Setup Complete ==="