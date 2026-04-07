#!/bin/bash
echo "=== Setting up Medicaid Coverage Gaps and Islands Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

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
  EXECUTE IMMEDIATE 'DROP USER medicaid_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# ---------------------------------------------------------------
# 3. Create MEDICAID_ANALYST schema
# ---------------------------------------------------------------
echo "Creating MEDICAID_ANALYST schema..."
oracle_query "CREATE USER medicaid_analyst IDENTIFIED BY Medicaid2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO medicaid_analyst;
GRANT RESOURCE TO medicaid_analyst;
GRANT CREATE VIEW TO medicaid_analyst;
GRANT CREATE PROCEDURE TO medicaid_analyst;
GRANT CREATE SESSION TO medicaid_analyst;
GRANT CREATE TABLE TO medicaid_analyst;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create medicaid_analyst user"
    exit 1
fi

# ---------------------------------------------------------------
# 4. Create schema tables and load exact test data
# ---------------------------------------------------------------
echo "Creating tables and loading data..."

sudo docker exec -i oracle-xe sqlplus -s medicaid_analyst/Medicaid2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE beneficiaries (
    beneficiary_id NUMBER PRIMARY KEY,
    first_name VARCHAR2(50),
    last_name VARCHAR2(50),
    dob DATE,
    gender VARCHAR2(1),
    county_code VARCHAR2(3)
);

CREATE TABLE enrollment_spans (
    span_id NUMBER PRIMARY KEY,
    beneficiary_id NUMBER REFERENCES beneficiaries(beneficiary_id),
    plan_type VARCHAR2(20),
    start_date DATE,
    end_date DATE,
    status VARCHAR2(20)
);

-- Insert Beneficiaries
INSERT INTO beneficiaries VALUES (1, 'John', 'Doe', DATE '1980-01-15', 'M', '001');
INSERT INTO beneficiaries VALUES (2, 'Jane', 'Smith', DATE '1992-05-22', 'F', '002');
INSERT INTO beneficiaries VALUES (3, 'Alice', 'Johnson', DATE '1975-11-08', 'F', '001');
INSERT INTO beneficiaries VALUES (4, 'Bob', 'Williams', DATE '1988-03-30', 'M', '003');
INSERT INTO beneficiaries VALUES (5, 'Charlie', 'Brown', DATE '2000-07-12', 'M', '002');

-- B1: Overlapping spans (1 gap of 31 days in July)
INSERT INTO enrollment_spans VALUES (101, 1, 'MCO-A', DATE '2023-01-01', DATE '2023-03-31', 'ACTIVE');
INSERT INTO enrollment_spans VALUES (102, 1, 'FFS',   DATE '2023-03-15', DATE '2023-06-30', 'ACTIVE');
INSERT INTO enrollment_spans VALUES (103, 1, 'MCO-B', DATE '2023-08-01', DATE '2023-12-31', 'ACTIVE');

-- B2: Contiguous spans + large gap (Gap of 62 days in Jul/Aug)
INSERT INTO enrollment_spans VALUES (201, 2, 'MCO-A', DATE '2023-01-01', DATE '2023-04-30', 'ACTIVE');
INSERT INTO enrollment_spans VALUES (202, 2, 'MCO-A', DATE '2023-05-01', DATE '2023-06-30', 'ACTIVE');
INSERT INTO enrollment_spans VALUES (203, 2, 'MCO-B', DATE '2023-09-01', DATE '2023-12-31', 'ACTIVE');

-- B3: Subsumed spans (Continuous all year, span inside a span)
INSERT INTO enrollment_spans VALUES (301, 3, 'MCO-C', DATE '2023-01-01', DATE '2023-12-31', 'ACTIVE');
INSERT INTO enrollment_spans VALUES (302, 3, 'FFS',   DATE '2023-04-01', DATE '2023-08-31', 'ACTIVE');

-- B4: Multiple small gaps (10 days in April, 20 days in Sept)
INSERT INTO enrollment_spans VALUES (401, 4, 'MCO-A', DATE '2023-01-01', DATE '2023-03-31', 'ACTIVE');
INSERT INTO enrollment_spans VALUES (402, 4, 'MCO-B', DATE '2023-04-11', DATE '2023-08-31', 'ACTIVE');
INSERT INTO enrollment_spans VALUES (403, 4, 'MCO-C', DATE '2023-09-21', DATE '2023-12-31', 'ACTIVE');

-- B5: Fails total days criteria
INSERT INTO enrollment_spans VALUES (501, 5, 'FFS',   DATE '2023-01-01', DATE '2023-06-30', 'ACTIVE');
INSERT INTO enrollment_spans VALUES (502, 5, 'MCO-A', DATE '2023-08-01', DATE '2023-10-31', 'ACTIVE');

COMMIT;
EXIT;
EOSQL
echo "Data loaded successfully."

# ---------------------------------------------------------------
# 5. Ensure export directory exists
# ---------------------------------------------------------------
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/hedis_2023_report.csv

# ---------------------------------------------------------------
# 6. Configure SQL Developer Connection
# ---------------------------------------------------------------
echo "Configuring SQL Developer connection..."
ensure_hr_connection "Medicaid Database" "medicaid_analyst" "Medicaid2024"

# ---------------------------------------------------------------
# 7. Start SQL Developer if not running
# ---------------------------------------------------------------
if ! pgrep -f "sqldeveloper" > /dev/null; then
    echo "Starting SQL Developer..."
    su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 JAVA_TOOL_OPTIONS='--add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/sun.net.www.protocol.jar=ALL-UNNAMED --add-opens=java.base/sun.net.www=ALL-UNNAMED --add-opens=java.desktop/sun.awt=ALL-UNNAMED --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED -Dsun.java2d.xrender=false -Dsun.java2d.opengl=false' /opt/sqldeveloper/sqldeveloper.sh > /tmp/sqldeveloper.log 2>&1 &"
    
    echo "Waiting for SQL Developer window..."
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
            echo "SQL Developer window detected."
            break
        fi
        sleep 1
    done
fi

sleep 5
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Setup complete ==="