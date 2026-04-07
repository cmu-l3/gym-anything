#!/bin/bash
echo "=== Setting up Loan Tampering Flashback Investigation Task ==="

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

# Ensure high UNDO retention for flashback queries
oracle_query "ALTER SYSTEM SET undo_retention = 86400 SCOPE=BOTH;" "system" > /dev/null 2>&1

# Drop and recreate user
echo "Setting up LENDING_ADMIN schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER lending_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

oracle_query "CREATE USER lending_admin IDENTIFIED BY Lending2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO lending_admin;
GRANT RESOURCE TO lending_admin;
GRANT CREATE TABLE TO lending_admin;
GRANT CREATE TRIGGER TO lending_admin;
GRANT CREATE SEQUENCE TO lending_admin;
GRANT SELECT ANY TRANSACTION TO lending_admin;
GRANT EXECUTE ON DBMS_FLASHBACK TO lending_admin;
EXIT;" "system"

# Setup baseline tables and data
echo "Creating tables and generating baseline data..."
sudo docker exec -i oracle-xe sqlplus -s lending_admin/Lending2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE MEMBERS (
    member_id NUMBER PRIMARY KEY,
    first_name VARCHAR2(50),
    last_name VARCHAR2(50),
    credit_score NUMBER,
    join_date DATE
);

CREATE TABLE LOAN_ACCOUNTS (
    loan_id NUMBER PRIMARY KEY,
    member_id NUMBER REFERENCES MEMBERS(member_id),
    loan_type VARCHAR2(50),
    original_amount NUMBER(12,2),
    current_balance NUMBER(12,2),
    interest_rate NUMBER(5,2),
    origination_date DATE,
    status VARCHAR2(20)
);

-- Insert synthetic members
BEGIN
  FOR i IN 1..30 LOOP
    INSERT INTO MEMBERS VALUES (
      1000 + i, 'FirstName'||i, 'LastName'||i, 
      TRUNC(DBMS_RANDOM.VALUE(550, 850)),
      SYSDATE - TRUNC(DBMS_RANDOM.VALUE(100, 3000))
    );
  END LOOP;
END;
/

-- Insert synthetic loans
BEGIN
  FOR i IN 1..50 LOOP
    INSERT INTO LOAN_ACCOUNTS VALUES (
      1000 + i, 
      1000 + TRUNC(DBMS_RANDOM.VALUE(1, 30)),
      CASE MOD(i,3) WHEN 0 THEN 'AUTO' WHEN 1 THEN 'MORTGAGE' ELSE 'PERSONAL' END,
      TRUNC(DBMS_RANDOM.VALUE(10000, 300000)),
      TRUNC(DBMS_RANDOM.VALUE(5000, 250000)),
      TRUNC(DBMS_RANDOM.VALUE(4.0, 14.0), 2),
      SYSDATE - TRUNC(DBMS_RANDOM.VALUE(30, 1500)),
      CASE WHEN DBMS_RANDOM.VALUE < 0.9 THEN 'ACTIVE' ELSE 'DEFAULT' END
    );
  END LOOP;
  
  -- Set specific baseline values for the 7 target loans so we know exactly what they are
  UPDATE LOAN_ACCOUNTS SET interest_rate = 6.50, current_balance = 12500.00, status = 'ACTIVE' WHERE loan_id = 1005;
  UPDATE LOAN_ACCOUNTS SET interest_rate = 5.75, current_balance = 15000.00, status = 'ACTIVE' WHERE loan_id = 1012;
  UPDATE LOAN_ACCOUNTS SET interest_rate = 7.20, current_balance = 8400.00,  status = 'ACTIVE' WHERE loan_id = 1023;
  UPDATE LOAN_ACCOUNTS SET interest_rate = 14.50, current_balance = 24000.00, status = 'DEFAULT' WHERE loan_id = 1034;
  UPDATE LOAN_ACCOUNTS SET interest_rate = 9.50, current_balance = 4500.00,  status = 'ACTIVE' WHERE loan_id = 1041;
  UPDATE LOAN_ACCOUNTS SET interest_rate = 8.00, current_balance = 32000.00, status = 'LATE'   WHERE loan_id = 1045;
  UPDATE LOAN_ACCOUNTS SET interest_rate = 12.00, current_balance = 18000.00, status = 'ACTIVE' WHERE loan_id = 1049;
END;
/
COMMIT;
EXIT;
EOSQL

# Save Ground Truth
mkdir -p /var/lib/task_ground_truth
cat > /var/lib/task_ground_truth/loan_ground_truth.json << 'EOF'
{
  "1005": {"interest_rate": 6.50, "current_balance": 12500.00, "status": "ACTIVE"},
  "1012": {"interest_rate": 5.75, "current_balance": 15000.00, "status": "ACTIVE"},
  "1023": {"interest_rate": 7.20, "current_balance": 8400.00,  "status": "ACTIVE"},
  "1034": {"interest_rate": 14.50, "current_balance": 24000.00, "status": "DEFAULT"},
  "1041": {"interest_rate": 9.50, "current_balance": 4500.00,  "status": "ACTIVE"},
  "1045": {"interest_rate": 8.00, "current_balance": 32000.00, "status": "LATE"},
  "1049": {"interest_rate": 12.00, "current_balance": 18000.00, "status": "ACTIVE"}
}
EOF
chmod 700 /var/lib/task_ground_truth
chmod 600 /var/lib/task_ground_truth/loan_ground_truth.json
chown root:root /var/lib/task_ground_truth -R 2>/dev/null || true

# Get PRE-TAMPERING SCN
echo "Capturing Pre-Tampering SCN..."
PRE_SCN=$(oracle_query_raw "SELECT current_scn FROM v\$database;" "system" | tr -d '[:space:]')
echo "Pre-Tampering SCN: $PRE_SCN"

sleep 3 # Ensure timestamp boundary

# Tamper with the loans
echo "Injecting unauthorized modifications..."
sudo docker exec -i oracle-xe sqlplus -s lending_admin/Lending2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF
UPDATE LOAN_ACCOUNTS SET interest_rate = 4.50 WHERE loan_id = 1005;
UPDATE LOAN_ACCOUNTS SET current_balance = 5000.00 WHERE loan_id = 1012;
UPDATE LOAN_ACCOUNTS SET interest_rate = 5.20 WHERE loan_id = 1023;
UPDATE LOAN_ACCOUNTS SET current_balance = 0.00, status = 'ACTIVE' WHERE loan_id = 1034;
UPDATE LOAN_ACCOUNTS SET interest_rate = 5.50 WHERE loan_id = 1041;
UPDATE LOAN_ACCOUNTS SET interest_rate = 4.00, status = 'ACTIVE' WHERE loan_id = 1045;
UPDATE LOAN_ACCOUNTS SET interest_rate = 6.00 WHERE loan_id = 1049;
COMMIT;
EXIT;
EOSQL

# Generate Incident Report
cat > /home/ga/Desktop/incident_report.txt << EOF
=================================================================
INCIDENT ALERT: UNAUTHORIZED DATA MODIFICATION DETECTED
=================================================================
Severity: CRITICAL
System: LENDING_SCHEMA
Table: LOAN_ACCOUNTS

Alert Details:
A routine database integrity check detected multiple anomalous 
modifications to active loan accounts outside of authorized 
business hours. 

Pre-tampering System Change Number (SCN): $PRE_SCN

Action Required:
1. Identify all modified loan records.
2. Determine their original values prior to the SCN listed above.
3. Document the findings in an INVESTIGATION_FINDINGS table.
4. Restore the affected records to their original states.
5. Implement audit tracking on the LOAN_ACCOUNTS table to 
   prevent future untracked modifications.
=================================================================
EOF
chown ga:ga /home/ga/Desktop/incident_report.txt

# Create pre-configured connection for SQL Developer
ensure_hr_connection "Lending DB" "lending_admin" "Lending2024"

# Launch SQL Developer
echo "Launching Oracle SQL Developer..."
su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper &"

# Wait for UI
echo "Waiting for SQL Developer window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql"; then
        break
    fi
    sleep 1
done

sleep 5

# Maximize SQL Developer
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss startup tips/dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Try to open the connection
open_hr_connection_in_sqldeveloper

# Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task Setup Complete ==="