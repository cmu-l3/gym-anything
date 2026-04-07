#!/bin/bash
# Setup script for Court Case Management Data Quality Audit task
echo "=== Setting up Court Data Quality Audit Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER court_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

echo "Creating COURT_ADMIN user..."
oracle_query "CREATE USER court_admin IDENTIFIED BY Court2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO court_admin;
GRANT RESOURCE TO court_admin;
GRANT CREATE VIEW TO court_admin;
GRANT CREATE PROCEDURE TO court_admin;
GRANT CREATE TRIGGER TO court_admin;
GRANT CREATE SESSION TO court_admin;
GRANT CREATE TABLE TO court_admin;
GRANT CREATE SEQUENCE TO court_admin;
EXIT;" "system"

echo "Creating Schema Tables..."
sudo docker exec -i oracle-xe sqlplus -s court_admin/Court2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE judges (
    judge_id NUMBER PRIMARY KEY,
    judge_name VARCHAR2(100) NOT NULL,
    courtroom VARCHAR2(20),
    appointment_date DATE,
    status VARCHAR2(20)
);

CREATE TABLE attorneys (
    attorney_id NUMBER PRIMARY KEY,
    bar_number VARCHAR2(20) UNIQUE,
    attorney_name VARCHAR2(100) NOT NULL,
    firm_name VARCHAR2(150),
    phone VARCHAR2(20),
    email VARCHAR2(100),
    status VARCHAR2(20)
);

CREATE TABLE parties (
    party_id NUMBER PRIMARY KEY,
    party_name VARCHAR2(150) NOT NULL,
    party_type VARCHAR2(30),
    date_of_birth DATE,
    address VARCHAR2(250),
    phone VARCHAR2(20)
);

CREATE TABLE cases (
    case_id NUMBER PRIMARY KEY,
    case_number VARCHAR2(30) UNIQUE NOT NULL,
    case_type VARCHAR2(50),
    filing_date DATE NOT NULL,
    status VARCHAR2(20),
    assigned_judge_id NUMBER REFERENCES judges(judge_id),
    courtroom VARCHAR2(20),
    disposition_date DATE,
    disposition VARCHAR2(100)
);

-- Note: attorney_id is intentionally a soft FK to allow orphan injection
CREATE TABLE case_parties (
    case_party_id NUMBER PRIMARY KEY,
    case_id NUMBER REFERENCES cases(case_id),
    party_id NUMBER REFERENCES parties(party_id),
    role VARCHAR2(30),
    attorney_id NUMBER 
);

-- Note: case_id is intentionally a soft FK to allow orphan injection
CREATE TABLE hearings (
    hearing_id NUMBER PRIMARY KEY,
    case_id NUMBER,
    hearing_date DATE NOT NULL,
    hearing_type VARCHAR2(50),
    courtroom VARCHAR2(20),
    judge_id NUMBER REFERENCES judges(judge_id),
    status VARCHAR2(20),
    notes VARCHAR2(500)
);

CREATE TABLE documents (
    document_id NUMBER PRIMARY KEY,
    case_id NUMBER REFERENCES cases(case_id),
    document_type VARCHAR2(50),
    filing_date DATE,
    filed_by VARCHAR2(100),
    description VARCHAR2(250),
    page_count NUMBER
);

CREATE TABLE fees (
    fee_id NUMBER PRIMARY KEY,
    case_id NUMBER REFERENCES cases(case_id),
    party_id NUMBER REFERENCES parties(party_id),
    fee_type VARCHAR2(50),
    amount NUMBER(10,2),
    paid_amount NUMBER(10,2),
    due_date DATE,
    paid_date DATE,
    status VARCHAR2(20)
);
EXIT;
EOSQL

echo "Generating Baseline Data and Injecting Flaws..."
sudo docker exec -i oracle-xe sqlplus -s court_admin/Court2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET SERVEROUTPUT ON
BEGIN
  -- 1. Generate Baseline Data
  FOR i IN 1..5 LOOP
    INSERT INTO judges VALUES (i, 'Judge '||i, 'Courtroom '||i, SYSDATE-1000, 'ACTIVE');
  END LOOP;
  
  FOR i IN 1..20 LOOP
    INSERT INTO attorneys VALUES (i, 'BAR'||TO_CHAR(10000+i), 'Attorney '||i, 'Firm '||i, '555-010'||i, 'att'||i||'@firm.com', 'ACTIVE');
  END LOOP;
  
  FOR i IN 1..100 LOOP
    INSERT INTO parties VALUES (i, 'Party '||i, CASE WHEN MOD(i,2)=0 THEN 'INDIVIDUAL' ELSE 'BUSINESS' END, SYSDATE-10000, '123 Main St', '555-020'||i);
  END LOOP;
  
  FOR i IN 1..200 LOOP
    INSERT INTO cases VALUES (i, '2024-CV-'||TO_CHAR(i, 'FM0000'), 'Civil', SYSDATE-300+i, 'OPEN', MOD(i,5)+1, 'Courtroom '||(MOD(i,5)+1), NULL, NULL);
  END LOOP;
  
  FOR i IN 1..400 LOOP
    INSERT INTO case_parties VALUES (i, MOD(i,200)+1, MOD(i,100)+1, CASE WHEN MOD(i,2)=0 THEN 'PLAINTIFF' ELSE 'DEFENDANT' END, MOD(i,20)+1);
  END LOOP;
  
  FOR i IN 1..300 LOOP
    INSERT INTO hearings VALUES (i, MOD(i,200)+1, SYSDATE-100+i, 'Status Conference', 'Courtroom 1', 1, 'COMPLETED', 'Initial hearing');
  END LOOP;
  
  FOR i IN 1..250 LOOP
    INSERT INTO fees VALUES (i, MOD(i,200)+1, MOD(i,100)+1, 'Filing Fee', 150.00, 150.00, SYSDATE-100+i, SYSDATE-100+i, 'PAID');
  END LOOP;

  -- 2. Inject Category 1: Orphaned Records
  INSERT INTO hearings (hearing_id, case_id, hearing_date, hearing_type, courtroom, judge_id, status, notes)
    SELECT 900+LEVEL, 99990+LEVEL, SYSDATE+10, 'Motion', 'Court 1', 1, 'SCHEDULED', 'Orphan' 
    FROM DUAL CONNECT BY LEVEL <= 5;
    
  UPDATE case_parties SET attorney_id = 9999 WHERE case_party_id IN (10, 20, 30, 40);

  -- 3. Inject Category 2: Temporal Violations
  UPDATE hearings h SET hearing_date = (SELECT filing_date - 15 FROM cases c WHERE c.case_id = h.case_id) 
    WHERE hearing_id IN (1, 2, 3, 4, 5, 6, 7, 8);
    
  UPDATE cases SET disposition_date = filing_date - 10, disposition = 'Settled', status = 'CLOSED' 
    WHERE case_id IN (11, 12, 13, 14);

  -- 4. Inject Category 3: Status Inconsistencies
  UPDATE cases SET status = 'CLOSED', disposition_date = SYSDATE-20, disposition = 'Dismissed' 
    WHERE case_id IN (21, 22, 23, 24, 25, 26);
  UPDATE hearings SET hearing_date = SYSDATE+30, status = 'SCHEDULED' 
    WHERE case_id IN (21, 22, 23, 24, 25, 26);
    
  UPDATE cases SET status = 'OPEN', disposition = 'Judgement Entered', disposition_date = SYSDATE-5 
    WHERE case_id IN (31, 32, 33, 34);

  -- 5. Inject Category 4: Duplicates (Same plaintiff, same type, within 30 days)
  INSERT INTO cases (case_id, case_number, case_type, filing_date, status, assigned_judge_id, courtroom, disposition_date, disposition)
    SELECT 800+ROWNUM, '2024-CV-'||TO_CHAR(800+ROWNUM, 'FM0000'), case_type, filing_date+2, status, assigned_judge_id, courtroom, disposition_date, disposition 
    FROM cases WHERE case_id IN (41, 42, 43);
    
  INSERT INTO case_parties (case_party_id, case_id, party_id, role, attorney_id)
    SELECT 800+ROWNUM, 800+ROWNUM, party_id, role, attorney_id 
    FROM case_parties WHERE case_id IN (41, 42, 43) AND role = 'PLAINTIFF';

  -- 6. Inject Category 5: Fee Anomalies
  UPDATE fees SET paid_amount = amount + 50.00 WHERE fee_id IN (51, 52, 53);
  
  UPDATE cases SET status = 'CLOSED', disposition_date = SYSDATE-100, disposition = 'Closed' 
    WHERE case_id IN (61, 62, 63, 64, 65);
  UPDATE fees SET status = 'UNPAID', paid_amount = 0, due_date = SYSDATE-95 
    WHERE case_id IN (61, 62, 63, 64, 65);

  COMMIT;
END;
/
EXIT;
EOSQL

echo "Data loaded successfully."

# Ensure SQL Developer has a pre-configured connection to COURT_ADMIN
ensure_hr_connection "Court Admin DB" "court_admin" "Court2024"

# Open SQL Developer
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="