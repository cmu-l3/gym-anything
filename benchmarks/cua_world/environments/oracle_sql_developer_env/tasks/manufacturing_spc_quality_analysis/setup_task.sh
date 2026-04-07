#!/bin/bash
# Setup script for Manufacturing SPC Quality Analysis task
echo "=== Setting up Manufacturing SPC Quality Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# Clean up previous run artifacts
echo "Cleaning up previous schema if exists..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER qc_engineer CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# Create QC_ENGINEER schema
echo "Creating QC_ENGINEER user..."
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
CREATE USER qc_engineer IDENTIFIED BY Quality2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;

GRANT CONNECT TO qc_engineer;
GRANT RESOURCE TO qc_engineer;
GRANT CREATE VIEW TO qc_engineer;
GRANT CREATE MATERIALIZED VIEW TO qc_engineer;
GRANT CREATE PROCEDURE TO qc_engineer;
GRANT CREATE SESSION TO qc_engineer;
GRANT CREATE TABLE TO qc_engineer;
GRANT CREATE SEQUENCE TO qc_engineer;
EXIT;
EOSQL
echo "QC_ENGINEER user created with required privileges."

# Create Tables and Populate Data
echo "Creating tables and populating SPC data (this may take a moment)..."
sudo docker exec -i oracle-xe sqlplus -s qc_engineer/Quality2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET SERVEROUTPUT ON
SET FEEDBACK OFF

-- Create sequences
CREATE SEQUENCE run_seq START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE meas_seq START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE def_seq START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE viol_seq START WITH 1 INCREMENT BY 1 NOCACHE;

-- Create tables
CREATE TABLE production_lines (
    line_id NUMBER PRIMARY KEY,
    line_name VARCHAR2(50),
    facility VARCHAR2(50),
    product_type VARCHAR2(50),
    rated_capacity_per_shift NUMBER
);

CREATE TABLE parts (
    part_id NUMBER PRIMARY KEY,
    part_number VARCHAR2(20),
    part_name VARCHAR2(100),
    material VARCHAR2(50),
    usl NUMBER,
    lsl NUMBER,
    target_value NUMBER,
    unit_of_measure VARCHAR2(20),
    drawing_revision VARCHAR2(10)
);

CREATE TABLE operators (
    operator_id NUMBER PRIMARY KEY,
    operator_name VARCHAR2(100),
    certification_level VARCHAR2(20),
    hire_date DATE,
    line_id NUMBER REFERENCES production_lines(line_id)
);

CREATE TABLE instruments (
    instrument_id NUMBER PRIMARY KEY,
    instrument_name VARCHAR2(100),
    instrument_type VARCHAR2(50),
    accuracy_class VARCHAR2(20),
    calibration_date DATE,
    next_calibration_date DATE,
    calibration_certificate VARCHAR2(50)
);

CREATE TABLE production_runs (
    run_id NUMBER PRIMARY KEY,
    line_id NUMBER REFERENCES production_lines(line_id),
    part_id NUMBER REFERENCES parts(part_id),
    run_date DATE,
    shift VARCHAR2(10),
    operator_id NUMBER REFERENCES operators(operator_id),
    batch_size NUMBER,
    accepted_qty NUMBER,
    rejected_qty NUMBER,
    run_status VARCHAR2(20)
);

CREATE TABLE measurements (
    measurement_id NUMBER PRIMARY KEY,
    run_id NUMBER REFERENCES production_runs(run_id),
    part_id NUMBER REFERENCES parts(part_id),
    sample_number NUMBER,
    measurement_value NUMBER,
    measurement_timestamp TIMESTAMP,
    instrument_id NUMBER REFERENCES instruments(instrument_id)
);

CREATE TABLE defects (
    defect_id NUMBER PRIMARY KEY,
    run_id NUMBER REFERENCES production_runs(run_id),
    part_id NUMBER REFERENCES parts(part_id),
    defect_type VARCHAR2(50),
    defect_count NUMBER,
    severity VARCHAR2(10)
);

-- Insert reference data
INSERT INTO production_lines VALUES (1, 'Stamping', 'Plant A - Detroit', 'Brake System', 1000);
INSERT INTO production_lines VALUES (2, 'CNC Machining', 'Plant A - Detroit', 'Powertrain', 500);
INSERT INTO production_lines VALUES (3, 'Assembly', 'Plant B - Chicago', 'Engine Components', 800);
INSERT INTO production_lines VALUES (4, 'Finishing', 'Plant B - Chicago', 'Various', 1200);

INSERT INTO parts VALUES (1, 'BR-4501-A', 'Brake Rotor', 'Cast Iron', 25.050, 24.950, 25.000, 'mm', 'Rev B');
INSERT INTO parts VALUES (2, 'PR-2200-C', 'Piston Ring', 'Steel', 0.500, 0.250, 0.375, 'mm', 'Rev A');
INSERT INTO parts VALUES (3, 'BH-8820-X', 'Bearing Housing', 'Aluminum', 52.010, 51.990, 52.000, 'mm', 'Rev C');
INSERT INTO parts VALUES (4, 'CS-1001-D', 'Camshaft', 'Forged Steel', 30.020, 29.980, 30.000, 'mm', 'Rev A');
INSERT INTO parts VALUES (5, 'CJ-3055-Y', 'Crankshaft Journal', 'Steel', 58.015, 57.985, 58.000, 'mm', 'Rev B');
INSERT INTO parts VALUES (6, 'VS-4040-Z', 'Valve Spring', 'Spring Steel', 49.000, 48.000, 48.500, 'mm', 'Rev D');

INSERT INTO operators VALUES (101, 'John Smith', 'Level II', DATE '2020-05-15', 1);
INSERT INTO operators VALUES (102, 'Maria Garcia', 'Level III', DATE '2018-03-10', 2);
INSERT INTO operators VALUES (103, 'David Chen', 'Level I', DATE '2023-01-20', 3);
INSERT INTO operators VALUES (104, 'Sarah Johnson', 'Level II', DATE '2019-11-05', 4);

INSERT INTO instruments VALUES (1001, 'Mitutoyo CMM #3', 'CMM', '0.001mm', DATE '2023-12-01', DATE '2024-12-01', 'CERT-9921');
INSERT INTO instruments VALUES (1002, 'Starrett Micrometer #12', 'Micrometer', '0.005mm', DATE '2023-01-15', DATE '2023-07-15', 'CERT-4432'); -- OVERDUE!
INSERT INTO instruments VALUES (1003, 'Hexagon Absolute Arm', 'CMM', '0.005mm', DATE '2024-06-10', DATE '2025-06-10', 'CERT-1129');

COMMIT;

-- Generate realistic measurement data using PL/SQL with specific quality signal injections
DECLARE
  v_date DATE;
  v_run_id NUMBER := 1;
  v_meas_id NUMBER := 1;
  v_target NUMBER;
  v_stddev NUMBER;
  v_val NUMBER;
  v_shift NUMBER;
  v_drift NUMBER;
  v_rej NUMBER;
BEGIN
  -- 90 days of production (July - Sep 2024)
  FOR d IN 0..90 LOOP
    v_date := DATE '2024-07-01' + d;
    
    -- Scenario 1: Brake Rotor (Part 1, Line 1) - Sudden mean shift at day 60 (+0.020mm)
    v_shift := CASE WHEN d >= 60 THEN 0.020 ELSE 0 END;
    v_rej := CASE WHEN d >= 60 THEN ROUND(DBMS_RANDOM.VALUE(5, 15)) ELSE ROUND(DBMS_RANDOM.VALUE(0, 3)) END;
    INSERT INTO production_runs VALUES (v_run_id, 1, 1, v_date, 'Day', 101, 1000, 1000-v_rej, v_rej, 'COMPLETED');
    FOR s IN 1..5 LOOP
      -- Normal variation ~ 0.008mm stddev
      v_val := 25.000 + v_shift + (DBMS_RANDOM.NORMAL * 0.008);
      INSERT INTO measurements VALUES (v_meas_id, v_run_id, 1, s, v_val, CAST(v_date + (s/24) AS TIMESTAMP), 1001);
      v_meas_id := v_meas_id + 1;
    END LOOP;
    v_run_id := v_run_id + 1;

    -- Scenario 2: Bearing Housing (Part 3, Line 2) - Gradual mean drift starting day 30 (+0.0003mm/day)
    v_drift := CASE WHEN d >= 30 THEN (d - 30) * 0.0003 ELSE 0 END;
    v_rej := CASE WHEN d >= 75 THEN ROUND(DBMS_RANDOM.VALUE(4, 10)) ELSE ROUND(DBMS_RANDOM.VALUE(0, 2)) END;
    INSERT INTO production_runs VALUES (v_run_id, 2, 3, v_date, 'Night', 102, 500, 500-v_rej, v_rej, 'COMPLETED');
    FOR s IN 1..5 LOOP
      -- Normal variation ~ 0.003mm stddev
      v_val := 52.000 + v_drift + (DBMS_RANDOM.NORMAL * 0.003);
      INSERT INTO measurements VALUES (v_meas_id, v_run_id, 3, s, v_val, CAST(v_date + (s/24) AS TIMESTAMP), 1002);
      v_meas_id := v_meas_id + 1;
    END LOOP;
    v_run_id := v_run_id + 1;

    -- Scenario 3: Valve Spring (Part 6, Line 3) - Increased variation starting day 45 (Stddev jumps from 0.1 to 0.35)
    v_stddev := CASE WHEN d >= 45 THEN 0.35 ELSE 0.10 END;
    v_rej := CASE WHEN d >= 45 THEN ROUND(DBMS_RANDOM.VALUE(10, 25)) ELSE ROUND(DBMS_RANDOM.VALUE(1, 5)) END;
    INSERT INTO production_runs VALUES (v_run_id, 3, 6, v_date, 'Swing', 103, 800, 800-v_rej, v_rej, 'COMPLETED');
    FOR s IN 1..5 LOOP
      v_val := 48.500 + (DBMS_RANDOM.NORMAL * v_stddev);
      INSERT INTO measurements VALUES (v_meas_id, v_run_id, 6, s, v_val, CAST(v_date + (10/24) + (s/24) AS TIMESTAMP), 1003);
      v_meas_id := v_meas_id + 1;
    END LOOP;
    v_run_id := v_run_id + 1;
    
    -- Baseline Scenario (Part 4, Line 4) - Stable Process
    INSERT INTO production_runs VALUES (v_run_id, 4, 4, v_date, 'Day', 104, 1200, 1198, 2, 'COMPLETED');
    FOR s IN 1..5 LOOP
      v_val := 30.000 + (DBMS_RANDOM.NORMAL * 0.005);
      INSERT INTO measurements VALUES (v_meas_id, v_run_id, 4, s, v_val, CAST(v_date + (5/24) + (s/24) AS TIMESTAMP), 1001);
      v_meas_id := v_meas_id + 1;
    END LOOP;
    v_run_id := v_run_id + 1;

  END LOOP;
  COMMIT;
END;
/

-- Generate Defects (Pareto distribution)
DECLARE
  v_def_id NUMBER := 1;
  PROCEDURE add_def(p_run NUMBER, p_part NUMBER, p_type VARCHAR2, p_count NUMBER, p_sev VARCHAR2) IS
  BEGIN
    INSERT INTO defects VALUES (v_def_id, p_run, p_part, p_type, p_count, p_sev);
    v_def_id := v_def_id + 1;
  END;
BEGIN
  FOR r IN 1..90 LOOP
    -- Most frequent defect
    add_def(r, 1, 'Surface Scratch', ROUND(DBMS_RANDOM.VALUE(2, 8)), 'MINOR');
    
    -- Less frequent
    IF MOD(r, 2) = 0 THEN
      add_def(r, 3, 'Dimensional OOT', ROUND(DBMS_RANDOM.VALUE(1, 4)), 'MAJOR');
    END IF;
    
    IF MOD(r, 4) = 0 THEN
      add_def(r, 6, 'Porosity', ROUND(DBMS_RANDOM.VALUE(1, 3)), 'CRITICAL');
    END IF;
    
    IF MOD(r, 7) = 0 THEN
      add_def(r, 4, 'Burrs', 1, 'MINOR');
    END IF;
    
    IF MOD(r, 15) = 0 THEN
      add_def(r, 1, 'Tool Marks', 1, 'MINOR');
    END IF;
    
    IF MOD(r, 30) = 0 THEN
      add_def(r, 6, 'Cracks', 1, 'CRITICAL');
    END IF;
  END LOOP;
  COMMIT;
END;
/
EXIT;
EOSQL
echo "Data generated successfully."

# Pre-configure SQL Developer Connection
echo "Pre-configuring QC Database connection in SQL Developer..."
ensure_hr_connection "QC Database" "qc_engineer" "Quality2024"

# Wait a moment for UI to settle
sleep 3

# Attempt to open the connection in the GUI
open_hr_connection_in_sqldeveloper

# Take initial screenshot
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="