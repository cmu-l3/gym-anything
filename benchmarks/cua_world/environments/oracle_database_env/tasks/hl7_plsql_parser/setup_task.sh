#!/bin/bash
# Setup script for HL7 PL/SQL Parser task
# Generates realistic HL7 v2.5 data and populates RAW_HL7_LOG

set -e

echo "=== Setting up HL7 Parser Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight checks ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

echo "[2/4] Verifying HR schema..."
wait_for_oracle 300

# --- Clean Setup ---
echo "[3/4] Preparing Database Objects..."

# SQL to create source table and populate with realistic HL7 data
# We use a PL/SQL block to generate data to avoid shipping a large static file
# We include specific "Sentinel" records for exact verification

cat > /tmp/setup_hl7.sql << 'EOF'
-- Clean up previous attempts
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE patient_admissions CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE raw_hl7_log CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Create Source Table
CREATE TABLE raw_hl7_log (
    log_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message_body CLOB,
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Procedure to generate realistic HL7 messages
DECLARE
    v_hl7 CLOB;
    v_mrn VARCHAR2(20);
    v_last VARCHAR2(50);
    v_first VARCHAR2(50);
    v_dob VARCHAR2(8);
    v_sex VARCHAR2(1);
    v_admit_date VARCHAR2(14);
    v_event VARCHAR2(7) := 'ADT^A01';
    v_diag VARCHAR2(20);
    
    TYPE t_str_array IS TABLE OF VARCHAR2(50);
    v_lasts t_str_array := t_str_array('Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez','Martinez');
    v_firsts t_str_array := t_str_array('James','Mary','Robert','Patricia','John','Jennifer','Michael','Linda','David','Elizabeth');
    v_diags t_str_array := t_str_array('E11.9','I10','J01.90','M54.5','R07.9','K21.9','E78.5','J45.909');
    
BEGIN
    -- 1. Insert 99 Random records
    FOR i IN 1..99 LOOP
        v_mrn := 'MRN' || LPAD(i, 6, '0');
        v_last := v_lasts(ROUND(DBMS_RANDOM.VALUE(1,10)));
        v_first := v_firsts(ROUND(DBMS_RANDOM.VALUE(1,10)));
        v_dob := TO_CHAR(SYSDATE - DBMS_RANDOM.VALUE(365*20, 365*80), 'YYYYMMDD');
        IF DBMS_RANDOM.VALUE > 0.5 THEN v_sex := 'M'; ELSE v_sex := 'F'; END IF;
        
        -- Mix date formats (some with HHMM, some without)
        IF DBMS_RANDOM.VALUE > 0.3 THEN
            v_admit_date := TO_CHAR(SYSDATE - DBMS_RANDOM.VALUE(0,30), 'YYYYMMDDHH24MI');
        ELSE
            v_admit_date := TO_CHAR(SYSDATE - DBMS_RANDOM.VALUE(0,30), 'YYYYMMDD');
        END IF;
        
        -- Build MSH
        v_hl7 := 'MSH|^~\&|EPIC|HOSP|LIS|LAB|' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') || '||' || v_event || '|MSG' || i || '|P|2.5' || CHR(13);
        
        -- Build PID
        v_hl7 := v_hl7 || 'PID|1||' || v_mrn || '^^^MRN||' || v_last || '^' || v_first || '||' || v_dob || '|' || v_sex || CHR(13);
        
        -- Build PV1 (Field 44 is Admit Date)
        v_hl7 := v_hl7 || 'PV1|1|I|200^01^01^^||||||||||||||||||||||||||||||||||||||||||||' || v_admit_date || CHR(13);
        
        -- Build DG1 (80% chance)
        IF DBMS_RANDOM.VALUE > 0.2 THEN
            v_diag := v_diags(ROUND(DBMS_RANDOM.VALUE(1,8)));
            v_hl7 := v_hl7 || 'DG1|1|I10|' || v_diag || '^Description^I10|||A';
        END IF;

        INSERT INTO raw_hl7_log (message_body) VALUES (v_hl7);
    END LOOP;
    
    -- 2. Insert Sentinel Record (Known Data for Verification)
    -- MRN: TEST999, Name: Everdeen^Katniss, Date: 202511221030, Diag: J01.90
    v_hl7 := 'MSH|^~\&|EPIC|HOSP|LIS|LAB|202511221030||ADT^A01|MSG999|P|2.5' || CHR(13) ||
             'PID|1||TEST999^^^MRN||Everdeen^Katniss^^^||19900101|F' || CHR(13) ||
             'PV1|1|I|300^01^01^^||||||||||||||||||||||||||||||||||||||||||||202511221030' || CHR(13) ||
             'DG1|1|I10|J01.90^Acute sinusitis^I10|||A';
             
    INSERT INTO raw_hl7_log (message_body) VALUES (v_hl7);
    
    COMMIT;
END;
/
EOF

# Execute setup SQL
sudo docker exec -i "$ORACLE_CONTAINER" sqlplus -s hr/hr123@localhost:1521/XEPDB1 < /tmp/setup_hl7.sql

# --- Record Initial State ---
echo "[4/4] Recording initial state..."
date +%s > /tmp/task_start_time

# Verify rows loaded
ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM raw_hl7_log;" "hr" | tr -d ' ')
echo "Loaded $ROW_COUNT HL7 messages into RAW_HL7_LOG"
echo "$ROW_COUNT" > /tmp/initial_row_count.txt

# Ensure DBeaver is available (likely tool used by agent)
if ! pgrep -f dbeaver > /dev/null; then
    echo "DBeaver available in menu."
fi

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="