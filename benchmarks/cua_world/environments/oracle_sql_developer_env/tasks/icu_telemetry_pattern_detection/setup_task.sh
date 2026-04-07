#!/bin/bash
echo "=== Setting up ICU Telemetry Pattern Detection Task ==="

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

# --- Clean up and recreate the CLINICAL_ADMIN user ---
echo "Setting up CLINICAL_ADMIN schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER clinical_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER clinical_admin IDENTIFIED BY Clinical2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO clinical_admin;
GRANT RESOURCE TO clinical_admin;
GRANT CREATE VIEW TO clinical_admin;
GRANT CREATE MATERIALIZED VIEW TO clinical_admin;
GRANT CREATE PROCEDURE TO clinical_admin;
GRANT CREATE SESSION TO clinical_admin;
GRANT CREATE TABLE TO clinical_admin;
EXIT;" "system"

echo "CLINICAL_ADMIN user created with required privileges"

# --- Create tables in CLINICAL schema ---
echo "Creating PATIENTS and RAW_FHIR_EVENTS tables..."
sudo docker exec -i oracle-xe sqlplus -s clinical_admin/Clinical2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE patients (
    patient_id NUMBER PRIMARY KEY,
    name VARCHAR2(100),
    admission_date DATE
);

CREATE TABLE raw_fhir_events (
    event_id NUMBER PRIMARY KEY,
    payload CLOB
        CONSTRAINT ensure_json CHECK (payload IS JSON)
);

CREATE SEQUENCE event_seq START WITH 1 INCREMENT BY 1;

-- Seed Patients
INSERT INTO patients VALUES (10045, 'John Doe', SYSDATE - 5);
INSERT INTO patients VALUES (20091, 'Jane Smith', SYSDATE - 2);
INSERT INTO patients VALUES (30555, 'Alice Johnson', SYSDATE - 1);

-- Generate realistic FHIR JSON payloads with specific patterns
DECLARE
    v_time TIMESTAMP := TIMESTAMP '2024-03-15 10:00:00';
    v_payload CLOB;
BEGIN
    -- ==========================================================
    -- PATIENT 10045: Normal, then missing data, then Tachycardia
    -- ==========================================================
    
    -- Normal baseline
    FOR i IN 1..3 LOOP
        v_payload := '{"resourceType":"Observation","subject":{"reference":"Patient/10045"},"effectiveDateTime":"' ||
                     TO_CHAR(v_time + numtodsinterval(i*10, 'MINUTE'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') || '",' ||
                     '"components":[{"code":"8867-4","valueQuantity":{"value":75}},{"code":"8480-6","valueQuantity":{"value":115}},{"code":"15074-8","valueQuantity":{"value":95}}]}';
        INSERT INTO raw_fhir_events VALUES (event_seq.NEXTVAL, v_payload);
    END LOOP;
    
    -- TACHYCARDIA PATTERN: Strictly increasing HR (4+ readings), starts >= 90, ends >= 120
    -- Sequence: 90, 100, 110, 120, 125
    FOR i IN 1..5 LOOP
        v_payload := '{"resourceType":"Observation","subject":{"reference":"Patient/10045"},"effectiveDateTime":"' ||
                     TO_CHAR(v_time + numtodsinterval(30 + i*5, 'MINUTE'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') || '",' ||
                     '"components":[{"code":"8867-4","valueQuantity":{"value":' || (80 + i*10 - CASE WHEN i=5 THEN 5 ELSE 0 END) || '}},{"code":"8480-6","valueQuantity":{"value":125}},{"code":"15074-8","valueQuantity":{"value":92}}]}';
        INSERT INTO raw_fhir_events VALUES (event_seq.NEXTVAL, v_payload);
    END LOOP;

    -- ==========================================================
    -- PATIENT 20091: Hypoglycemia pattern with MISSING data packet
    -- ==========================================================
    
    -- Normal reading
    v_payload := '{"resourceType":"Observation","subject":{"reference":"Patient/20091"},"effectiveDateTime":"' ||
                 TO_CHAR(v_time, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') || '",' ||
                 '"components":[{"code":"8867-4","valueQuantity":{"value":80}},{"code":"8480-6","valueQuantity":{"value":110}},{"code":"15074-8","valueQuantity":{"value":100}}]}';
    INSERT INTO raw_fhir_events VALUES (event_seq.NEXTVAL, v_payload);
    
    -- Drop to 65 (<70)
    v_payload := '{"resourceType":"Observation","subject":{"reference":"Patient/20091"},"effectiveDateTime":"' ||
                 TO_CHAR(v_time + numtodsinterval(15, 'MINUTE'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') || '",' ||
                 '"components":[{"code":"8867-4","valueQuantity":{"value":82}},{"code":"8480-6","valueQuantity":{"value":108}},{"code":"15074-8","valueQuantity":{"value":65}}]}';
    INSERT INTO raw_fhir_events VALUES (event_seq.NEXTVAL, v_payload);
    
    -- MISSING glucose reading (simulating dropped sensor data). HR and BP are present.
    -- If IGNORE NULLS is used, this will carry forward the 65.
    v_payload := '{"resourceType":"Observation","subject":{"reference":"Patient/20091"},"effectiveDateTime":"' ||
                 TO_CHAR(v_time + numtodsinterval(30, 'MINUTE'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') || '",' ||
                 '"components":[{"code":"8867-4","valueQuantity":{"value":85}},{"code":"8480-6","valueQuantity":{"value":105}}]}';
    INSERT INTO raw_fhir_events VALUES (event_seq.NEXTVAL, v_payload);
    
    -- Drop to 60 (<70)
    v_payload := '{"resourceType":"Observation","subject":{"reference":"Patient/20091"},"effectiveDateTime":"' ||
                 TO_CHAR(v_time + numtodsinterval(45, 'MINUTE'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') || '",' ||
                 '"components":[{"code":"8867-4","valueQuantity":{"value":88}},{"code":"8480-6","valueQuantity":{"value":102}},{"code":"15074-8","valueQuantity":{"value":60}}]}';
    INSERT INTO raw_fhir_events VALUES (event_seq.NEXTVAL, v_payload);
    
    -- Drop to 58 (<70). Total sequence of <70: 65, (65 imputed), 60, 58 -> 4 consecutive!
    v_payload := '{"resourceType":"Observation","subject":{"reference":"Patient/20091"},"effectiveDateTime":"' ||
                 TO_CHAR(v_time + numtodsinterval(60, 'MINUTE'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') || '",' ||
                 '"components":[{"code":"8867-4","valueQuantity":{"value":92}},{"code":"8480-6","valueQuantity":{"value":100}},{"code":"15074-8","valueQuantity":{"value":58}}]}';
    INSERT INTO raw_fhir_events VALUES (event_seq.NEXTVAL, v_payload);
    
    -- Recovery to 80
    v_payload := '{"resourceType":"Observation","subject":{"reference":"Patient/20091"},"effectiveDateTime":"' ||
                 TO_CHAR(v_time + numtodsinterval(75, 'MINUTE'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') || '",' ||
                 '"components":[{"code":"8867-4","valueQuantity":{"value":85}},{"code":"15074-8","valueQuantity":{"value":80}}]}';
    INSERT INTO raw_fhir_events VALUES (event_seq.NEXTVAL, v_payload);
    
    COMMIT;
END;
/
EXIT;
EOSQL
echo "FHIR JSON payload data generated successfully."

# Setup export directory
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Pre-configure Clinical connection in SQL Developer
ensure_hr_connection "Clinical Database" "clinical_admin" "Clinical2024"

# Launch SQL Developer via existing shortcut
echo "Launching Oracle SQL Developer..."
su - ga -c "DISPLAY=:1 gtk-launch SQLDeveloper.desktop > /dev/null 2>&1 &"

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
        echo "SQL Developer window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize and Focus
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Open connection if possible
open_hr_connection_in_sqldeveloper 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task Setup Complete ==="