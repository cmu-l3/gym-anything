#!/bin/bash
# Setup script for Water Utility Pipe Infrastructure Failure Analysis task
echo "=== Setting up Water Utility Pipe Infrastructure Failure Analysis ==="

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

# --- Drop and recreate the water_eng user cleanly ---
echo "Setting up WATER_ENG schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER water_eng CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER water_eng IDENTIFIED BY Water2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO water_eng;
GRANT RESOURCE TO water_eng;
GRANT CREATE VIEW TO water_eng;
GRANT CREATE MATERIALIZED VIEW TO water_eng;
GRANT CREATE PROCEDURE TO water_eng;
GRANT CREATE SESSION TO water_eng;
GRANT CREATE TABLE TO water_eng;
GRANT CREATE TYPE TO water_eng;
EXIT;" "system"

# --- Create tables ---
echo "Creating tables and generating data..."
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'

-- 1. PRESSURE_ZONES
CREATE TABLE water_eng.pressure_zones (
    zone_id NUMBER PRIMARY KEY,
    zone_name VARCHAR2(100),
    zone_priority NUMBER,
    service_population NUMBER,
    avg_pressure_psi NUMBER
);

-- 2. PIPE_MATERIALS
CREATE TABLE water_eng.pipe_materials (
    material_id NUMBER PRIMARY KEY,
    material_name VARCHAR2(100),
    expected_life_years NUMBER,
    risk_ranking NUMBER,
    cost_per_foot NUMBER
);

-- 3. PIPE_SEGMENTS
CREATE TABLE water_eng.pipe_segments (
    pipe_id NUMBER PRIMARY KEY,
    segment_code VARCHAR2(50),
    material_id NUMBER REFERENCES water_eng.pipe_materials(material_id),
    zone_id NUMBER REFERENCES water_eng.pressure_zones(zone_id),
    diameter_inches NUMBER,
    length_feet NUMBER,
    install_year NUMBER,
    street_name VARCHAR2(100),
    city_quadrant VARCHAR2(2),
    depth_feet NUMBER,
    lining_type VARCHAR2(50),
    is_active NUMBER(1),
    last_inspection_date DATE
);

-- 4. BREAK_HISTORY
CREATE TABLE water_eng.break_history (
    break_id NUMBER PRIMARY KEY,
    pipe_id NUMBER REFERENCES water_eng.pipe_segments(pipe_id),
    break_date DATE,
    break_type VARCHAR2(50),
    cause VARCHAR2(100),
    repair_cost NUMBER,
    repair_duration_hours NUMBER,
    customers_affected NUMBER,
    main_or_service VARCHAR2(10),
    reported_by VARCHAR2(50)
);

-- 5. WATER_QUALITY
CREATE TABLE water_eng.water_quality (
    reading_id NUMBER PRIMARY KEY,
    station_id NUMBER,
    zone_id NUMBER REFERENCES water_eng.pressure_zones(zone_id),
    sample_date DATE,
    parameter_name VARCHAR2(50),
    value NUMBER,
    unit VARCHAR2(20),
    mcl_limit NUMBER,
    violation_flag NUMBER(1)
);

-- Insert reference data
INSERT INTO water_eng.pressure_zones VALUES (1, 'Downtown Core', 1, 85000, 75);
INSERT INTO water_eng.pressure_zones VALUES (2, 'North Hills', 2, 60000, 90);
INSERT INTO water_eng.pressure_zones VALUES (3, 'South Valley', 3, 45000, 65);
INSERT INTO water_eng.pressure_zones VALUES (4, 'Eastside Industrial', 1, 20000, 80);
INSERT INTO water_eng.pressure_zones VALUES (5, 'Westside Residential', 4, 75000, 60);

INSERT INTO water_eng.pipe_materials VALUES (1, 'Cast Iron', 75, 5, 250);
INSERT INTO water_eng.pipe_materials VALUES (2, 'Asbestos Cement', 60, 4, 180);
INSERT INTO water_eng.pipe_materials VALUES (3, 'Ductile Iron', 80, 3, 220);
INSERT INTO water_eng.pipe_materials VALUES (4, 'PVC', 100, 2, 120);
INSERT INTO water_eng.pipe_materials VALUES (5, 'HDPE', 100, 1, 140);

COMMIT;

-- Generate realistic pipe segments and breaks using PL/SQL
DECLARE
    v_pipe_id NUMBER := 1;
    v_break_id NUMBER := 1;
    v_material NUMBER;
    v_year NUMBER;
    v_breaks_count NUMBER;
    v_break_date DATE;
BEGIN
    FOR m IN 1..5 LOOP
        FOR d IN 1..4 LOOP
            -- Decades: 1960, 1970, 1980, 1990
            v_year := 1950 + (d * 10);
            
            -- Create 50 pipes for each material/decade
            FOR p IN 1..50 LOOP
                INSERT INTO water_eng.pipe_segments VALUES (
                    v_pipe_id, 'SEG-' || v_pipe_id, m, MOD(v_pipe_id, 5) + 1, 
                    8, 500 + MOD(v_pipe_id, 500), v_year + MOD(p, 10), 
                    'Street ' || v_pipe_id, 'NW', 4, 'None', 1, SYSDATE - 365
                );
                
                -- Generate some random breaks for older pipes
                v_breaks_count := CASE 
                                    WHEN m = 1 THEN MOD(v_pipe_id, 4) -- Cast iron breaks more
                                    WHEN m = 2 THEN MOD(v_pipe_id, 3) 
                                    ELSE MOD(v_pipe_id, 2)
                                  END;
                                  
                FOR b IN 1..v_breaks_count LOOP
                    INSERT INTO water_eng.break_history VALUES (
                        v_break_id, v_pipe_id, 
                        TO_DATE('2000-01-01', 'YYYY-MM-DD') + (b * 365 * 2) + MOD(v_pipe_id, 100), 
                        'CIRCUMFERENTIAL', 'CORROSION', 5000, 6, 20, 'MAIN', 'PUBLIC'
                    );
                    v_break_id := v_break_id + 1;
                END LOOP;
                
                v_pipe_id := v_pipe_id + 1;
            END LOOP;
        END LOOP;
    END LOOP;
    
    -- Insert specific escalating failure patterns for MATCH_RECOGNIZE to find
    -- Pipe 1001: Accelerating breaks
    INSERT INTO water_eng.pipe_segments VALUES (1001, 'SEG-1001', 1, 1, 12, 1000, 1965, 'Main St', 'NW', 5, 'None', 1, SYSDATE);
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1001, TO_DATE('2010-01-01', 'YYYY-MM-DD'), 'LEAK', 'CORROSION', 1000, 4, 10, 'MAIN', 'CREW'); v_break_id := v_break_id+1;
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1001, TO_DATE('2015-01-01', 'YYYY-MM-DD'), 'LEAK', 'CORROSION', 1000, 4, 10, 'MAIN', 'CREW'); v_break_id := v_break_id+1; -- 5 yrs
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1001, TO_DATE('2018-01-01', 'YYYY-MM-DD'), 'LEAK', 'CORROSION', 1000, 4, 10, 'MAIN', 'CREW'); v_break_id := v_break_id+1; -- 3 yrs
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1001, TO_DATE('2019-01-01', 'YYYY-MM-DD'), 'LEAK', 'CORROSION', 1000, 4, 10, 'MAIN', 'CREW'); v_break_id := v_break_id+1; -- 1 yr
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1001, TO_DATE('2019-06-01', 'YYYY-MM-DD'), 'LEAK', 'CORROSION', 1000, 4, 10, 'MAIN', 'CREW'); v_break_id := v_break_id+1; -- 0.5 yr
    
    -- Pipe 1002: Accelerating breaks
    INSERT INTO water_eng.pipe_segments VALUES (1002, 'SEG-1002', 2, 2, 8, 800, 1970, 'Oak Ave', 'NE', 4, 'None', 1, SYSDATE);
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1002, TO_DATE('2005-01-01', 'YYYY-MM-DD'), 'SPLIT', 'PRESSURE', 2000, 6, 50, 'MAIN', 'CREW'); v_break_id := v_break_id+1;
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1002, TO_DATE('2011-01-01', 'YYYY-MM-DD'), 'SPLIT', 'PRESSURE', 2000, 6, 50, 'MAIN', 'CREW'); v_break_id := v_break_id+1; -- 6 yrs
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1002, TO_DATE('2015-01-01', 'YYYY-MM-DD'), 'SPLIT', 'PRESSURE', 2000, 6, 50, 'MAIN', 'CREW'); v_break_id := v_break_id+1; -- 4 yrs
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1002, TO_DATE('2017-01-01', 'YYYY-MM-DD'), 'SPLIT', 'PRESSURE', 2000, 6, 50, 'MAIN', 'CREW'); v_break_id := v_break_id+1; -- 2 yrs
    
    -- Pipe 1003: Constant breaks (not accelerating, should be ignored by MATCH_RECOGNIZE)
    INSERT INTO water_eng.pipe_segments VALUES (1003, 'SEG-1003', 1, 1, 12, 1000, 1965, 'Elm St', 'SW', 5, 'None', 1, SYSDATE);
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1003, TO_DATE('2010-01-01', 'YYYY-MM-DD'), 'LEAK', 'CORROSION', 1000, 4, 10, 'MAIN', 'CREW'); v_break_id := v_break_id+1;
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1003, TO_DATE('2012-01-01', 'YYYY-MM-DD'), 'LEAK', 'CORROSION', 1000, 4, 10, 'MAIN', 'CREW'); v_break_id := v_break_id+1; -- 2 yrs
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1003, TO_DATE('2014-01-01', 'YYYY-MM-DD'), 'LEAK', 'CORROSION', 1000, 4, 10, 'MAIN', 'CREW'); v_break_id := v_break_id+1; -- 2 yrs
    INSERT INTO water_eng.break_history VALUES (v_break_id, 1003, TO_DATE('2016-01-01', 'YYYY-MM-DD'), 'LEAK', 'CORROSION', 1000, 4, 10, 'MAIN', 'CREW'); v_break_id := v_break_id+1; -- 2 yrs
    
    COMMIT;
END;
/
EXIT;
EOSQL

echo "Data generation complete."

# -------------------------------------------------------
# Configure SQL Developer connection
# -------------------------------------------------------
ensure_hr_connection "Water Infrastructure" "water_eng" "Water2024"

# -------------------------------------------------------
# Open SQL Developer
# -------------------------------------------------------
open_hr_connection_in_sqldeveloper

# -------------------------------------------------------
# Take Initial Screenshot
# -------------------------------------------------------
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="