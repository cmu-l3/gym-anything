#!/bin/bash
# Setup script for Hospital Infection Contact Tracing task
echo "=== Setting up Hospital Infection Contact Tracing Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
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

# -------------------------------------------------------
# Clean up previous run artifacts
# -------------------------------------------------------
echo "Cleaning up previous run artifacts..."

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER ehr_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# -------------------------------------------------------
# Create the EHR_ANALYST user
# -------------------------------------------------------
echo "Creating EHR_ANALYST user..."
oracle_query "CREATE USER ehr_analyst IDENTIFIED BY EhrData2024
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON USERS;

GRANT CONNECT TO ehr_analyst;
GRANT RESOURCE TO ehr_analyst;
GRANT CREATE VIEW TO ehr_analyst;
GRANT CREATE MATERIALIZED VIEW TO ehr_analyst;
GRANT CREATE PROCEDURE TO ehr_analyst;
GRANT CREATE SESSION TO ehr_analyst;
GRANT CREATE TABLE TO ehr_analyst;
GRANT CREATE SEQUENCE TO ehr_analyst;
EXIT;" "system"

echo "EHR_ANALYST user created with required privileges."

# -------------------------------------------------------
# Create Tables and Insert Data
# -------------------------------------------------------
echo "Creating tables and populating with clinical data..."

sudo docker exec -i oracle-xe sqlplus -s ehr_analyst/EhrData2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- ADMISSIONS
CREATE TABLE admissions (
    subject_id          NUMBER,
    hadm_id             NUMBER PRIMARY KEY,
    admittime           DATE,
    dischtime           DATE,
    admission_type      VARCHAR2(50),
    hospital_expire_flag NUMBER
);

-- TRANSFERS
CREATE TABLE transfers (
    transfer_id NUMBER PRIMARY KEY,
    subject_id  NUMBER,
    hadm_id     NUMBER REFERENCES admissions(hadm_id),
    careunit    VARCHAR2(50),
    intime      DATE,
    outtime     DATE
);

-- MICROBIOLOGY
CREATE TABLE microbiology (
    micro_id    NUMBER PRIMARY KEY,
    subject_id  NUMBER,
    hadm_id     NUMBER REFERENCES admissions(hadm_id),
    chartdate   DATE,
    org_name    VARCHAR2(100),
    test_result VARCHAR2(20)
);

-- POPULATE DATA --

-- Index 1 (MRSA). Admitted 01-01, Discharged 01-15. Positive on 01-05.
-- Infectious from 01-03 to 01-15.
INSERT INTO admissions VALUES (100, 1000, TO_DATE('2024-01-01', 'YYYY-MM-DD'), TO_DATE('2024-01-15', 'YYYY-MM-DD'), 'EMERGENCY', 0);
INSERT INTO microbiology VALUES (1, 100, 1000, TO_DATE('2024-01-05', 'YYYY-MM-DD'), 'MRSA', 'POSITIVE');
INSERT INTO transfers VALUES (1, 100, 1000, 'WARD_A', TO_DATE('2024-01-01', 'YYYY-MM-DD'), TO_DATE('2024-01-08', 'YYYY-MM-DD'));
INSERT INTO transfers VALUES (2, 100, 1000, 'MICU', TO_DATE('2024-01-08', 'YYYY-MM-DD'), TO_DATE('2024-01-15', 'YYYY-MM-DD'));

-- Exposed 1. Admitted 01-04, NOT discharged. 
-- In WARD_A from 01-04 to 01-10. Overlaps with Index 1 from 01-04 to 01-08 (96 hrs). >= 12h.
-- SHOULD BE IN EXPOSURES AND GET ISOLATION ORDER.
INSERT INTO admissions VALUES (200, 2000, TO_DATE('2024-01-04', 'YYYY-MM-DD'), NULL, 'URGENT', 0);
INSERT INTO transfers VALUES (3, 200, 2000, 'WARD_A', TO_DATE('2024-01-04', 'YYYY-MM-DD'), TO_DATE('2024-01-10', 'YYYY-MM-DD'));

-- Exposed 2. Admitted 01-03, Discharged 01-03 10:00.
-- In WARD_A from 01-03 00:00 to 01-03 10:00. Overlaps with Index 1 from 01-03 to 01-03 10:00 (10 hrs). < 12h.
-- SHOULD NOT BE IN EXPOSURES.
INSERT INTO admissions VALUES (201, 2001, TO_DATE('2024-01-03', 'YYYY-MM-DD'), TO_DATE('2024-01-03 10:00:00', 'YYYY-MM-DD HH24:MI:SS'), 'ELECTIVE', 0);
INSERT INTO transfers VALUES (4, 201, 2001, 'WARD_A', TO_DATE('2024-01-03', 'YYYY-MM-DD'), TO_DATE('2024-01-03 10:00:00', 'YYYY-MM-DD HH24:MI:SS'));

-- Exposed 3. Admitted 01-08, Discharged 01-10.
-- In MICU from 01-08 to 01-10. Overlaps with Index 1 in MICU from 01-08 to 01-10 (48 hrs). >= 12h.
-- SHOULD BE IN EXPOSURES, BUT NO ISOLATION ORDER (already discharged).
INSERT INTO admissions VALUES (202, 2002, TO_DATE('2024-01-08', 'YYYY-MM-DD'), TO_DATE('2024-01-10', 'YYYY-MM-DD'), 'EMERGENCY', 0);
INSERT INTO transfers VALUES (5, 202, 2002, 'MICU', TO_DATE('2024-01-08', 'YYYY-MM-DD'), TO_DATE('2024-01-10', 'YYYY-MM-DD'));

-- Index 2 (C.DIFF). Admitted 02-01, NOT discharged. Positive on 02-05.
-- Infectious from 02-03 to SYSDATE.
INSERT INTO admissions VALUES (300, 3000, TO_DATE('2024-02-01', 'YYYY-MM-DD'), NULL, 'EMERGENCY', 0);
INSERT INTO microbiology VALUES (2, 300, 3000, TO_DATE('2024-02-05', 'YYYY-MM-DD'), 'C.DIFF', 'POSITIVE');
INSERT INTO transfers VALUES (6, 300, 3000, 'SICU', TO_DATE('2024-02-01', 'YYYY-MM-DD'), NULL);

-- Exposed 4. Admitted 02-04, NOT discharged.
-- In SICU from 02-04 to SYSDATE. Overlaps with Index 2 from 02-04 to SYSDATE (lots of hrs). >= 12h.
-- SHOULD BE IN EXPOSURES AND GET ISOLATION ORDER.
INSERT INTO admissions VALUES (400, 4000, TO_DATE('2024-02-04', 'YYYY-MM-DD'), NULL, 'EMERGENCY', 0);
INSERT INTO transfers VALUES (7, 400, 4000, 'SICU', TO_DATE('2024-02-04', 'YYYY-MM-DD'), NULL);

-- Non-exposed patient (different ward)
INSERT INTO admissions VALUES (500, 5000, TO_DATE('2024-03-01', 'YYYY-MM-DD'), NULL, 'ELECTIVE', 0);
INSERT INTO transfers VALUES (8, 500, 5000, 'WARD_B', TO_DATE('2024-03-01', 'YYYY-MM-DD'), NULL);

COMMIT;
EXIT;
EOSQL

echo "Data populated."

# -------------------------------------------------------
# Pre-configure HR Database connection in SQL Developer
# -------------------------------------------------------
ensure_hr_connection "EHR Database" "ehr_analyst" "EhrData2024"

# Open the connection in SQL Developer if it's already running
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Setup complete ==="