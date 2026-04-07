#!/bin/bash
# Setup script for Patient Data Encryption task
# Creates the PATIENT_RECORDS table with sensitive plaintext data
# Grants necessary privileges to HR user

set -e

echo "=== Setting up Patient Data Encryption Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Pre-flight: Verify HR schema connectivity ---
echo "[2/4] Verifying HR schema..."
for attempt in 1 2 3 4 5; do
    if oracle_query_raw "SELECT 1 FROM DUAL;" "hr" >/dev/null 2>&1; then
        echo "  HR schema ready."
        break
    fi
    echo "  Attempt $attempt failed, waiting 5s..."
    sleep 5
done

# --- Clean up prior artifacts and Create Table ---
echo "[3/4] Creating PATIENT_RECORDS table with synthetic data..."

# We use a PL/SQL block to generate realistic looking data
oracle_query "
BEGIN
    -- Cleanup
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE patient_records CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE encryption_key_store CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP VIEW patient_records_vw'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP FUNCTION encrypt_value'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP FUNCTION decrypt_value'; EXCEPTION WHEN OTHERS THEN NULL; END;

    -- Create Table
    EXECUTE IMMEDIATE 'CREATE TABLE patient_records (
        patient_id NUMBER(6) PRIMARY KEY,
        first_name VARCHAR2(50),
        last_name VARCHAR2(50),
        ssn VARCHAR2(11),
        date_of_birth DATE,
        diagnosis_code VARCHAR2(10),
        diagnosis_desc VARCHAR2(200),
        admission_date DATE,
        attending_physician VARCHAR2(100),
        department VARCHAR2(50)
    )';

    -- Grant Crypto Access
    EXECUTE IMMEDIATE 'GRANT EXECUTE ON DBMS_CRYPTO TO hr';
END;
/
" "system" > /dev/null

# Populate Data using PL/SQL for randomization
oracle_query "
DECLARE
    TYPE t_array IS TABLE OF VARCHAR2(100);
    v_first_names t_array := t_array('James','Mary','John','Patricia','Robert','Jennifer','Michael','Linda','William','Elizabeth','David','Barbara','Richard','Susan','Joseph','Jessica','Thomas','Sarah','Charles','Karen');
    v_last_names t_array := t_array('Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez','Martinez','Hernandez','Lopez','Gonzalez','Wilson','Anderson','Thomas','Taylor','Moore','Jackson','Martin');
    v_depts t_array := t_array('Cardiology','Oncology','Pediatrics','Neurology','Emergency','Orthopedics','General Surgery');
    v_diagnosis_codes t_array := t_array('E11.9','I10','J45.909','M54.5','J06.9','N39.0','E78.5','K21.9','F41.1','R07.9');
    v_diagnosis_descs t_array := t_array('Type 2 diabetes mellitus','Essential hypertension','Unspecified asthma','Low back pain','Acute upper respiratory infection','Urinary tract infection','Hyperlipidemia','Gastro-esophageal reflux','Generalized anxiety disorder','Chest pain, unspecified');
    
    v_ssn VARCHAR2(11);
    v_idx NUMBER;
    v_diag_idx NUMBER;
BEGIN
    FOR i IN 1..150 LOOP
        -- Generate fake SSN: XXX-XX-XXXX
        v_ssn := LPAD(TRUNC(DBMS_RANDOM.VALUE(100,999)),3,'0') || '-' || 
                 LPAD(TRUNC(DBMS_RANDOM.VALUE(10,99)),2,'0') || '-' || 
                 LPAD(TRUNC(DBMS_RANDOM.VALUE(1000,9999)),4,'0');
        
        v_diag_idx := TRUNC(DBMS_RANDOM.VALUE(1, 11));
        
        INSERT INTO patient_records VALUES (
            1000 + i,
            v_first_names(TRUNC(DBMS_RANDOM.VALUE(1, 21))),
            v_last_names(TRUNC(DBMS_RANDOM.VALUE(1, 21))),
            v_ssn,
            TO_DATE('1950-01-01','YYYY-MM-DD') + TRUNC(DBMS_RANDOM.VALUE(0, 20000)),
            v_diagnosis_codes(v_diag_idx),
            v_diagnosis_descs(v_diag_idx),
            SYSDATE - TRUNC(DBMS_RANDOM.VALUE(0, 365)),
            'Dr. ' || v_last_names(TRUNC(DBMS_RANDOM.VALUE(1, 21))),
            v_depts(TRUNC(DBMS_RANDOM.VALUE(1, 8)))
        );
    END LOOP;
    COMMIT;
END;
/
" "hr" > /dev/null

# --- Record Initial State ---
echo "[4/4] Recording initial state..."
ROW_COUNT=$(get_table_count "patient_records" "hr")
echo "$ROW_COUNT" > /tmp/initial_row_count.txt

# Save columns to file for anti-gaming check
oracle_query_raw "SELECT column_name, data_type FROM user_tab_columns WHERE table_name = 'PATIENT_RECORDS' ORDER BY column_id;" "hr" > /tmp/initial_columns.txt

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "Setup complete. Patient records created: $ROW_COUNT"