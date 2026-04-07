#!/bin/bash
echo "=== Setting up Spatial Hazard Proximity Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# -------------------------------------------------------
# Verify Oracle container is running
# -------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# Wait a moment to ensure DB listener is ready
sleep 5

# -------------------------------------------------------
# Clean up previous run artifacts
# -------------------------------------------------------
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER emergency_mgr CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

rm -f /home/ga/Documents/exports/evacuation_schools.csv 2>/dev/null || true
sleep 2

# -------------------------------------------------------
# Create EMERGENCY_MGR schema
# -------------------------------------------------------
echo "Creating EMERGENCY_MGR user..."
oracle_query "CREATE USER emergency_mgr IDENTIFIED BY RiskPlan2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO emergency_mgr;
GRANT RESOURCE TO emergency_mgr;
GRANT CREATE VIEW TO emergency_mgr;
GRANT CREATE PROCEDURE TO emergency_mgr;
GRANT CREATE SESSION TO emergency_mgr;
GRANT CREATE TABLE TO emergency_mgr;
GRANT CREATE TYPE TO emergency_mgr;
GRANT CREATE SEQUENCE TO emergency_mgr;
-- Give permissions needed for spatial indexes
GRANT CREATE INDEXTYPE TO emergency_mgr;
GRANT CREATE OPERATOR TO emergency_mgr;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create emergency_mgr user"
    exit 1
fi
echo "EMERGENCY_MGR user created with required privileges."

# -------------------------------------------------------
# Create and Populate INFRASTRUCTURE Table
# -------------------------------------------------------
echo "Creating and populating INFRASTRUCTURE table..."
sudo docker exec -i oracle-xe sqlplus -s emergency_mgr/RiskPlan2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE infrastructure (
    facility_id    NUMBER PRIMARY KEY,
    facility_name  VARCHAR2(200) NOT NULL,
    facility_type  VARCHAR2(50) NOT NULL,
    latitude       NUMBER(10,6) NOT NULL,
    longitude      NUMBER(10,6) NOT NULL
);

-- Seed explicit overlapping cases (guarantees rows in the view)
DECLARE
  v_id NUMBER := 1;
BEGIN
  -- 15 pairs of HAZMAT and SCHOOL located closely (within ~500m)
  -- 1 degree lat/lon is ~111km. 0.004 degrees is ~440m.
  FOR i IN 1..15 LOOP
    INSERT INTO infrastructure VALUES (v_id, 'Industrial Chemicals Inc '||i, 'HAZMAT', 25.7500 + (i*0.01), -80.2500 + (i*0.01));
    v_id := v_id + 1;
    INSERT INTO infrastructure VALUES (v_id, 'Coastal High School '||i, 'SCHOOL', 25.7500 + (i*0.01) + 0.004, -80.2500 + (i*0.01));
    v_id := v_id + 1;
  END LOOP;
  COMMIT;
END;
/

-- Seed random background noise using CONNECT BY for speed
-- Florida approximate bounding box: Lat 25.0 to 31.0, Lon -87.0 to -80.0
INSERT /*+ APPEND */ INTO infrastructure
SELECT 
    100 + ROWNUM, 
    'Public School ' || ROWNUM, 
    'SCHOOL', 
    25.0 + DBMS_RANDOM.VALUE(0, 6), 
    -87.0 + DBMS_RANDOM.VALUE(0, 7)
FROM DUAL CONNECT BY ROWNUM <= 4000;
COMMIT;

INSERT /*+ APPEND */ INTO infrastructure
SELECT 
    4100 + ROWNUM, 
    'General Hospital ' || ROWNUM, 
    'HOSPITAL', 
    25.0 + DBMS_RANDOM.VALUE(0, 6), 
    -87.0 + DBMS_RANDOM.VALUE(0, 7)
FROM DUAL CONNECT BY ROWNUM <= 150;
COMMIT;

INSERT /*+ APPEND */ INTO infrastructure
SELECT 
    4250 + ROWNUM, 
    'Manufacturing Facility ' || ROWNUM, 
    'HAZMAT', 
    25.0 + DBMS_RANDOM.VALUE(0, 6), 
    -87.0 + DBMS_RANDOM.VALUE(0, 7)
FROM DUAL CONNECT BY ROWNUM <= 300;
COMMIT;

EXIT;
EOSQL

echo "INFRASTRUCTURE table seeded with ~4,500 records."

# -------------------------------------------------------
# Pre-configure SQL Developer connection
# -------------------------------------------------------
echo "Configuring SQL Developer connection..."
ensure_hr_connection "Emergency Database" "emergency_mgr" "RiskPlan2024"

# -------------------------------------------------------
# Take initial screenshot for evidence
# -------------------------------------------------------
sleep 2
take_screenshot /tmp/task_initial_state.png ga

echo "=== Setup complete ==="