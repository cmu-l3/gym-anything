#!/bin/bash
echo "=== Setting up Assembly Line Pattern Detection Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# Clean up any previous runs
echo "Cleaning up PROD_ENGINEER schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER prod_engineer CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# Create PROD_ENGINEER user
echo "Creating PROD_ENGINEER schema..."
oracle_query "CREATE USER prod_engineer IDENTIFIED BY ProdEng2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE TO prod_engineer;
GRANT CREATE VIEW, CREATE MATERIALIZED VIEW TO prod_engineer;
GRANT CREATE PROCEDURE TO prod_engineer;
GRANT CREATE SESSION TO prod_engineer;
GRANT CREATE TABLE TO prod_engineer;
GRANT CREATE SEQUENCE TO prod_engineer;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create prod_engineer user"
    exit 1
fi

# Create Tables and Insert Data using PL/SQL block
echo "Building tables and injecting pattern data..."
sudo docker exec -i oracle-xe sqlplus -s prod_engineer/ProdEng2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON SERVEROUTPUT ON

CREATE TABLE assembly_lines (
    line_id NUMBER PRIMARY KEY,
    line_name VARCHAR2(50),
    product_type VARCHAR2(50),
    daily_target_units NUMBER
);

CREATE TABLE workstations (
    station_id NUMBER PRIMARY KEY,
    line_id NUMBER REFERENCES assembly_lines(line_id),
    station_name VARCHAR2(80),
    station_order NUMBER,
    station_type VARCHAR2(30)
);

CREATE TABLE shifts (
    shift_id NUMBER PRIMARY KEY,
    shift_name VARCHAR2(20),
    start_hour NUMBER,
    end_hour NUMBER
);

CREATE TABLE event_codes (
    event_code VARCHAR2(20) PRIMARY KEY,
    description VARCHAR2(200),
    category VARCHAR2(30),
    typical_duration_min NUMBER
);

CREATE TABLE station_events (
    event_id NUMBER PRIMARY KEY,
    station_id NUMBER REFERENCES workstations(station_id),
    event_timestamp TIMESTAMP,
    event_type VARCHAR2(30),
    event_code VARCHAR2(20) REFERENCES event_codes(event_code),
    severity NUMBER(1),
    quality_score NUMBER(5,2),
    operator_id NUMBER,
    shift_id NUMBER,
    notes VARCHAR2(500)
);

CREATE TABLE pattern_results (
    result_id NUMBER PRIMARY KEY,
    pattern_type VARCHAR2(30),
    detection_timestamp TIMESTAMP DEFAULT SYSTIMESTAMP,
    line_id NUMBER,
    start_station_id NUMBER,
    end_station_id NUMBER,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    duration_seconds NUMBER,
    num_events NUMBER,
    details VARCHAR2(1000)
);

CREATE SEQUENCE pattern_result_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE event_seq START WITH 1 INCREMENT BY 1;

-- Seed Dimensions
BEGIN
    INSERT INTO assembly_lines VALUES (1, 'Body Welding', 'Chassis', 450);
    INSERT INTO assembly_lines VALUES (2, 'Paint Shop', 'Coating', 400);
    INSERT INTO assembly_lines VALUES (3, 'Final Assembly', 'Trim', 420);

    -- Workstations Line 1
    INSERT INTO workstations VALUES (101, 1, 'Weld Cell A', 1, 'WELD');
    INSERT INTO workstations VALUES (102, 1, 'Weld Cell B', 2, 'WELD');
    INSERT INTO workstations VALUES (103, 1, 'Sealant Apply', 3, 'SEAL');
    INSERT INTO workstations VALUES (104, 1, 'Inspect A', 4, 'INSPECT');

    -- Workstations Line 2
    INSERT INTO workstations VALUES (201, 2, 'Primer', 1, 'PAINT');
    INSERT INTO workstations VALUES (202, 2, 'Base Coat', 2, 'PAINT');
    INSERT INTO workstations VALUES (203, 2, 'Clear Coat', 3, 'PAINT');
    INSERT INTO workstations VALUES (204, 2, 'Cure Oven', 4, 'CURE');

    -- Event Codes
    INSERT INTO event_codes VALUES ('RUN_01', 'Normal Operation', 'RUNNING', 60);
    INSERT INTO event_codes VALUES ('IDL_01', 'Scheduled Idle', 'IDLE', 15);
    INSERT INTO event_codes VALUES ('FLT_01', 'Robotic Arm Fault', 'FAULT', 10);
    INSERT INTO event_codes VALUES ('FLT_02', 'Sensor Timeout', 'FAULT', 5);
    INSERT INTO event_codes VALUES ('FLT_03', 'Conveyor Jam', 'FAULT', 15);
    INSERT INTO event_codes VALUES ('QC_01', 'Standard Quality Check', 'QUALITY_CHECK', 2);
    
    COMMIT;
END;
/

-- Seed Events (Background Noise + Injected Patterns)
DECLARE
    v_base_time TIMESTAMP := SYSTIMESTAMP - INTERVAL '90' DAY;
    v_ev_id NUMBER := 1;
    
    PROCEDURE ins_ev(p_st NUMBER, p_type VARCHAR2, p_code VARCHAR2, p_sev NUMBER, p_qs NUMBER, p_time TIMESTAMP) IS
    BEGIN
        INSERT INTO station_events VALUES (event_seq.NEXTVAL, p_st, p_time, p_type, p_code, p_sev, p_qs, 999, 1, NULL);
    END;
BEGIN
    -- Background noise (100 events)
    FOR i IN 1..100 LOOP
        ins_ev(101, 'RUNNING', 'RUN_01', 1, NULL, v_base_time + NUMTODSINTERVAL(i*10, 'MINUTE'));
        ins_ev(102, 'QUALITY_CHECK', 'QC_01', 1, 95 + DBMS_RANDOM.VALUE(0,4), v_base_time + NUMTODSINTERVAL(i*15, 'MINUTE'));
    END LOOP;

    -- INJECT PATTERN 1: Cascading Failures
    -- Cascade A: Line 1, St 101 -> St 102 -> St 103 (within 10 mins each)
    v_base_time := SYSTIMESTAMP - INTERVAL '80' DAY;
    ins_ev(101, 'FAULT', 'FLT_01', 4, NULL, v_base_time);
    ins_ev(102, 'FAULT', 'FLT_02', 3, NULL, v_base_time + INTERVAL '4' MINUTE);
    ins_ev(103, 'FAULT', 'FLT_03', 3, NULL, v_base_time + INTERVAL '7' MINUTE);
    
    -- Cascade B: Line 2, St 201 -> St 203 (within 10 mins)
    v_base_time := SYSTIMESTAMP - INTERVAL '70' DAY;
    ins_ev(201, 'FAULT', 'FLT_01', 5, NULL, v_base_time);
    ins_ev(203, 'FAULT', 'FLT_02', 3, NULL, v_base_time + INTERVAL '8' MINUTE);

    -- INJECT PATTERN 2: Quality Degradation
    -- Degrade A: 4 checks, dropping, final < 80
    v_base_time := SYSTIMESTAMP - INTERVAL '60' DAY;
    ins_ev(104, 'QUALITY_CHECK', 'QC_01', 1, 95.0, v_base_time);
    ins_ev(104, 'QUALITY_CHECK', 'QC_01', 1, 88.5, v_base_time + INTERVAL '1' HOUR);
    ins_ev(104, 'QUALITY_CHECK', 'QC_01', 1, 82.0, v_base_time + INTERVAL '2' HOUR);
    ins_ev(104, 'QUALITY_CHECK', 'QC_01', 1, 75.5, v_base_time + INTERVAL '3' HOUR);
    
    -- Degrade B: 5 checks, dropping, final < 80
    v_base_time := SYSTIMESTAMP - INTERVAL '50' DAY;
    ins_ev(204, 'QUALITY_CHECK', 'QC_01', 1, 98.0, v_base_time);
    ins_ev(204, 'QUALITY_CHECK', 'QC_01', 1, 92.0, v_base_time + INTERVAL '1' HOUR);
    ins_ev(204, 'QUALITY_CHECK', 'QC_01', 1, 85.0, v_base_time + INTERVAL '2' HOUR);
    ins_ev(204, 'QUALITY_CHECK', 'QC_01', 1, 81.0, v_base_time + INTERVAL '3' HOUR);
    ins_ev(204, 'QUALITY_CHECK', 'QC_01', 1, 78.0, v_base_time + INTERVAL '4' HOUR);

    -- INJECT PATTERN 3: Short Run Cycles
    -- Cycle A: Idle >20m, Run <30m, Idle >20m
    v_base_time := SYSTIMESTAMP - INTERVAL '40' DAY;
    ins_ev(101, 'IDLE', 'IDL_01', 1, NULL, v_base_time);
    ins_ev(101, 'RUNNING', 'RUN_01', 1, NULL, v_base_time + INTERVAL '25' MINUTE); -- Idle was 25m
    ins_ev(101, 'IDLE', 'IDL_01', 1, NULL, v_base_time + INTERVAL '40' MINUTE); -- Run was 15m
    ins_ev(101, 'RUNNING', 'RUN_01', 1, NULL, v_base_time + INTERVAL '70' MINUTE); -- Idle was 30m
    
    -- Cycle B
    v_base_time := SYSTIMESTAMP - INTERVAL '30' DAY;
    ins_ev(201, 'IDLE', 'IDL_01', 1, NULL, v_base_time);
    ins_ev(201, 'RUNNING', 'RUN_01', 1, NULL, v_base_time + INTERVAL '22' MINUTE);
    ins_ev(201, 'IDLE', 'IDL_01', 1, NULL, v_base_time + INTERVAL '45' MINUTE);
    ins_ev(201, 'RUNNING', 'RUN_01', 1, NULL, v_base_time + INTERVAL '75' MINUTE);

    COMMIT;
END;
/
EXIT;
EOSQL

# Pre-configure SQL Developer Connection
echo "Configuring SQL Developer connection..."
ensure_hr_connection "Prod Engineer DB" "prod_engineer" "ProdEng2024"

# Wait for GUI and bring it to front
sleep 15
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="