#!/bin/bash
# Setup script for DMV License Suspension Audit task
echo "=== Setting up DMV License Suspension Audit Task ==="

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

# Ensure export directory exists
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

# Clean up previous runs
echo "Setting up DMV schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER dmv_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER dmv_admin IDENTIFIED BY DmvAudit2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO dmv_admin;
GRANT RESOURCE TO dmv_admin;
GRANT CREATE VIEW TO dmv_admin;
GRANT CREATE MATERIALIZED VIEW TO dmv_admin;
GRANT CREATE SESSION TO dmv_admin;
GRANT CREATE TABLE TO dmv_admin;
EXIT;" "system"

echo "dmv_admin user created with required privileges"

# Create tables
echo "Creating schemas..."
sudo docker exec -i oracle-xe sqlplus -s dmv_admin/DmvAudit2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE drivers (
    driver_id       NUMBER PRIMARY KEY,
    license_number  VARCHAR2(20) UNIQUE NOT NULL,
    first_name      VARCHAR2(50) NOT NULL,
    last_name       VARCHAR2(50) NOT NULL,
    dob             DATE NOT NULL,
    license_class   VARCHAR2(2),
    license_status  VARCHAR2(20) NOT NULL,
    status_updated_date DATE
);

CREATE TABLE citation_types (
    violation_code  VARCHAR2(20) PRIMARY KEY,
    description     VARCHAR2(200) NOT NULL,
    points          NUMBER NOT NULL,
    fine_amount     NUMBER(8,2),
    is_criminal     NUMBER(1) DEFAULT 0
);

CREATE TABLE citations (
    citation_id     NUMBER PRIMARY KEY,
    driver_id       NUMBER REFERENCES drivers(driver_id),
    citation_date   DATE NOT NULL,
    violation_code  VARCHAR2(20) REFERENCES citation_types(violation_code),
    jurisdiction    VARCHAR2(50),
    officer_id      NUMBER,
    adjudication_status VARCHAR2(20) NOT NULL
);

EXIT;
EOSQL

# Generate realistic scale synthetic data via PL/SQL to avoid handwritten 3-row tables
echo "Populating large-scale realistic DMV datasets..."
sudo docker exec -i oracle-xe sqlplus -s dmv_admin/DmvAudit2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET SERVEROUTPUT ON
DECLARE
    v_driver_id NUMBER;
    v_date DATE;
    v_status VARCHAR2(20);
    v_code VARCHAR2(20);
BEGIN
    -- Base Citation Types
    INSERT INTO citation_types VALUES ('SPEEDING', 'Speeding 1-15mph over', 1, 150, 0);
    INSERT INTO citation_types VALUES ('SPEEDING_2', 'Speeding 16-25mph over', 2, 250, 0);
    INSERT INTO citation_types VALUES ('RECKLESS', 'Reckless Driving', 6, 1000, 1);
    INSERT INTO citation_types VALUES ('DUI', 'Driving Under Influence', 12, 2500, 1);
    INSERT INTO citation_types VALUES ('FAIL_STOP', 'Failure to Stop at Red Light', 2, 350, 0);
    INSERT INTO citation_types VALUES ('NO_INSURANCE', 'Driving Without Insurance', 4, 500, 0);

    -- Insert 5000 realistic drivers
    FOR i IN 1..5000 LOOP
        v_status := CASE WHEN MOD(i, 45) = 0 THEN 'SUSPENDED' ELSE 'ACTIVE' END;
        INSERT INTO drivers VALUES (
            i, 
            'DL' || LPAD(i, 7, '0'), 
            'FirstName' || i, 
            'LastName' || i, 
            TO_DATE('1970-01-01', 'YYYY-MM-DD') + MOD(i, 15000), 
            'C', 
            v_status, 
            SYSDATE - DBMS_RANDOM.VALUE(10, 300)
        );
    END LOOP;

    -- Insert 15000 realistic background citations (Years 2020-2024)
    FOR i IN 1..15000 LOOP
        v_driver_id := TRUNC(DBMS_RANDOM.VALUE(101, 5001));
        v_date := TO_DATE('2020-01-01', 'YYYY-MM-DD') + TRUNC(DBMS_RANDOM.VALUE(0, 1640));
        
        v_code := CASE MOD(i, 6) 
            WHEN 0 THEN 'SPEEDING' 
            WHEN 1 THEN 'RECKLESS' 
            WHEN 2 THEN 'FAIL_STOP' 
            WHEN 3 THEN 'SPEEDING_2'
            WHEN 4 THEN 'NO_INSURANCE'
            ELSE 'DUI' 
        END;
        
        INSERT INTO citations VALUES (
            i, v_driver_id, v_date, v_code, 'COUNTY_PD', 9000, 
            CASE WHEN MOD(i, 10) = 0 THEN 'DISMISSED' ELSE 'GUILTY' END
        );
    END LOOP;

    -- INJECT AUDIT ANOMALIES (GROUND TRUTH)
    
    -- Anomaly Type 1: MISSING_SUSPENSION (25 drivers)
    -- Drivers 1-25 are explicitly ACTIVE but will get two 6-point citations in the 2024 target window.
    FOR i IN 1..25 LOOP
        DELETE FROM citations WHERE driver_id = i AND citation_date >= TO_DATE('2023-01-01', 'YYYY-MM-DD');
        UPDATE drivers SET license_status = 'ACTIVE' WHERE driver_id = i;
        
        -- Two reckless citations (6 points each = 12 total rolling on 2024-05-10)
        INSERT INTO citations VALUES (20000 + (i*2), i, TO_DATE('2024-02-15', 'YYYY-MM-DD'), 'RECKLESS', 'STATE_HP', 801, 'GUILTY');
        INSERT INTO citations VALUES (20000 + (i*2) + 1, i, TO_DATE('2024-05-10', 'YYYY-MM-DD'), 'RECKLESS', 'STATE_HP', 802, 'GUILTY');
    END LOOP;

    -- Anomaly Type 2: INVALID_SUSPENSION (15 drivers)
    -- Drivers 26-40 are explicitly SUSPENDED but have 0 citations in the last two years.
    FOR i IN 26..40 LOOP
        DELETE FROM citations WHERE driver_id = i AND citation_date >= TO_DATE('2023-01-01', 'YYYY-MM-DD');
        UPDATE drivers SET license_status = 'SUSPENDED' WHERE driver_id = i;
        
        -- One old DUI from 2021
        INSERT INTO citations VALUES (30000 + i, i, TO_DATE('2021-06-15', 'YYYY-MM-DD'), 'DUI', 'STATE_HP', 803, 'GUILTY');
    END LOOP;

    -- Anomaly Type 3: OK Suspended (10 drivers)
    -- Drivers 41-50 are SUSPENDED and correctly hit 12 points in the 2024 window.
    FOR i IN 41..50 LOOP
        DELETE FROM citations WHERE driver_id = i AND citation_date >= TO_DATE('2023-01-01', 'YYYY-MM-DD');
        UPDATE drivers SET license_status = 'SUSPENDED' WHERE driver_id = i;
        
        INSERT INTO citations VALUES (40000 + i, i, TO_DATE('2024-03-20', 'YYYY-MM-DD'), 'DUI', 'STATE_HP', 804, 'GUILTY');
    END LOOP;

    COMMIT;
END;
/
EXIT;
EOSQL
echo "Realistic dataset generated successfully."

# Write the rules file to desktop
cat > /home/ga/Desktop/dmv_rules.txt << 'RULESEOF'
DMV License Suspension Audit Rules (Snapshot Date: 2024-07-01)

1. Penalty Points Calculation:
- Only citations with an adjudication_status other than 'DISMISSED' or 'WARNING' accrue points.
- The 12-month rolling points for any given citation is the sum of penalty points accumulated in the 1-year period leading up to (and including) that citation's date.
- You must use an Oracle temporal window function (RANGE BETWEEN INTERVAL '1' YEAR PRECEDING AND CURRENT ROW) over the citation_date.

2. Suspension Criteria:
- A driver's EXPECTED status as of 2024-07-01 is 'SUSPENDED' if they received *any* valid citation between '2024-01-01' and '2024-07-01' where their rolling 12-month points reached 12 or more.
- Otherwise, their EXPECTED status is 'ACTIVE'.

3. Audit Flags:
- If ACTUAL = ACTIVE and EXPECTED = SUSPENDED -> 'MISSING_SUSPENSION'
- If ACTUAL = SUSPENDED and EXPECTED = ACTIVE -> 'INVALID_SUSPENSION'
- If ACTUAL = EXPECTED -> 'OK'
RULESEOF
chown ga:ga /home/ga/Desktop/dmv_rules.txt

# Pre-configure SQL Developer connection
ensure_hr_connection "DMV Audit DB" "dmv_admin" "DmvAudit2024"

# Open SQL Developer directly to the connection
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task Setup Complete ==="