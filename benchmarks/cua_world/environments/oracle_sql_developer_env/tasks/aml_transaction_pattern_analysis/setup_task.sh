#!/bin/bash
# Setup script for AML Transaction Pattern Analysis task
echo "=== Setting up AML Transaction Pattern Analysis ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# 1. Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# 2. Clean up previous run artifacts
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER aml_investigator CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

rm -f /home/ga/aml_investigation_report.csv 2>/dev/null || true

# 3. Create AML_INVESTIGATOR schema
echo "Creating AML_INVESTIGATOR schema..."
oracle_query "CREATE USER aml_investigator IDENTIFIED BY AML2024Secure
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO aml_investigator;
GRANT RESOURCE TO aml_investigator;
GRANT CREATE VIEW TO aml_investigator;
GRANT CREATE PROCEDURE TO aml_investigator;
GRANT CREATE SESSION TO aml_investigator;
GRANT CREATE TABLE TO aml_investigator;
GRANT CREATE SEQUENCE TO aml_investigator;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create aml_investigator user"
    exit 1
fi
echo "AML_INVESTIGATOR user created."

# 4. Create specification file
cat > /home/ga/Desktop/aml_detection_rules.txt << 'EOF'
=== ANTI-MONEY LAUNDERING (AML) DETECTION SPECIFICATION ===

1. STRUCTURING (SMURFING) DETECTION PARAMETERS
- Pattern: Sequence of 3 or more cash deposits in the same account
- Individual Transaction Range: $3,000 to $9,999 (just below $10k CTR threshold)
- Time Window: All transactions in the sequence must occur within a 7-day period
- Cumulative Threshold: The sum of the sequence must exceed $10,000
- REQUIREMENT: Must use Oracle MATCH_RECOGNIZE clause.

2. LAYERING / RAPID MOVEMENT PARAMETERS
- Pattern: Incoming transfer followed rapidly by outgoing transfer
- Time Gap: Outgoing transfer occurs within 24 hours of incoming transfer
- Retention Threshold: Less than 5% of the incoming amount remains in the account (Outgoing Amount >= 95% of Incoming Amount)
- Minimum Amount: Applies to transaction chains over $10,000

3. FUND FLOW TRACING
- Trace multi-hop transfers (A -> B -> C -> D) up to 6 levels deep using CONNECT BY or WITH RECURSIVE.

4. COMPOSITE RISK SCORING MODEL (0-100 Scale)
Customer Risk Score = Sum of weighted factors (Cap at 100):
  A. Transaction Volume Anomaly (Weight: 20 pts)
     - Score = 20 if monthly avg > 3x peer group (customer_type) avg, else proportional.
  B. Jurisdiction Risk (Weight: 25 pts)
     - Score = 25 for BLACK_LIST, 15 for GREY_LIST, 0 for LOW risk.
  C. Structuring Frequency (Weight: 25 pts)
     - Score = MIN(25, 10 * number of structuring alerts)
  D. Rapid Movement / Layering (Weight: 15 pts)
     - Score = MIN(15, 7.5 * number of layering alerts)
  E. Round Amount Ratio (Weight: 15 pts)
     - Score = 15 * (percentage of transactions evenly divisible by 1000)

5. SAR RECOMMENDATION GENERATION
- Threshold: Any customer with Risk Score >= 60.
- Narrative: Use LISTAGG to combine all flagged reasons into a single text string per customer.
EOF
chown ga:ga /home/ga/Desktop/aml_detection_rules.txt

# 5. Create Schema Objects and Insert Data
echo "Creating schema objects and populating data..."
sudo docker exec -i oracle-xe sqlplus -s aml_investigator/AML2024Secure@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE jurisdiction_risk (
    country_code VARCHAR2(3) PRIMARY KEY,
    country_name VARCHAR2(100),
    fatf_status VARCHAR2(20),
    risk_level VARCHAR2(10),
    cpi_score NUMBER,
    basel_aml_score NUMBER
);

CREATE TABLE branches (
    branch_id NUMBER PRIMARY KEY,
    branch_name VARCHAR2(100),
    city VARCHAR2(50),
    state VARCHAR2(2),
    country VARCHAR2(3)
);

CREATE TABLE customers (
    customer_id NUMBER PRIMARY KEY,
    customer_name VARCHAR2(100),
    customer_type VARCHAR2(20),
    country_code VARCHAR2(3) REFERENCES jurisdiction_risk(country_code),
    city VARCHAR2(50),
    occupation VARCHAR2(100),
    kyc_date DATE,
    kyc_risk_rating VARCHAR2(10),
    annual_income NUMBER,
    account_purpose VARCHAR2(100)
);

CREATE TABLE accounts (
    account_id NUMBER PRIMARY KEY,
    customer_id NUMBER REFERENCES customers(customer_id),
    account_type VARCHAR2(20),
    open_date DATE,
    status VARCHAR2(10),
    branch_id NUMBER REFERENCES branches(branch_id),
    currency VARCHAR2(3)
);

CREATE TABLE transactions (
    txn_id NUMBER PRIMARY KEY,
    account_id NUMBER REFERENCES accounts(account_id),
    txn_type VARCHAR2(30),
    amount NUMBER(15,2),
    currency VARCHAR2(3),
    counterparty_account NUMBER,
    counterparty_name VARCHAR2(100),
    txn_date TIMESTAMP,
    channel VARCHAR2(20),
    branch_id NUMBER REFERENCES branches(branch_id),
    reference_note VARCHAR2(200),
    country_origin VARCHAR2(3),
    country_destination VARCHAR2(3)
);

-- Insert Jurisdictions
INSERT INTO jurisdiction_risk VALUES ('USA', 'United States', 'MEMBER', 'LOW', 69, 4.2);
INSERT INTO jurisdiction_risk VALUES ('GBR', 'United Kingdom', 'MEMBER', 'LOW', 73, 4.0);
INSERT INTO jurisdiction_risk VALUES ('IRN', 'Iran', 'BLACK_LIST', 'VERY_HIGH', 25, 8.1);
INSERT INTO jurisdiction_risk VALUES ('PRK', 'North Korea', 'BLACK_LIST', 'VERY_HIGH', 17, 8.3);
INSERT INTO jurisdiction_risk VALUES ('PAN', 'Panama', 'GREY_LIST', 'HIGH', 36, 6.5);
INSERT INTO jurisdiction_risk VALUES ('CYM', 'Cayman Islands', 'GREY_LIST', 'HIGH', 60, 5.8);

-- Insert Branches
INSERT INTO branches VALUES (101, 'NY Main', 'New York', 'NY', 'USA');
INSERT INTO branches VALUES (102, 'Miami Hub', 'Miami', 'FL', 'USA');
INSERT INTO branches VALUES (103, 'London City', 'London', NULL, 'GBR');

-- Insert Customers
-- Cust 1: Normal user
INSERT INTO customers VALUES (1, 'Alice Smith', 'INDIVIDUAL', 'USA', 'New York', 'Teacher', SYSDATE-1000, 'LOW', 75000, 'Salary');
-- Cust 2: Structuring Smurf
INSERT INTO customers VALUES (2, 'Bob Jones', 'INDIVIDUAL', 'USA', 'Miami', 'Cashier', SYSDATE-500, 'MEDIUM', 45000, 'Personal');
-- Cust 3: Shell Company (Layering node 1)
INSERT INTO customers VALUES (3, 'Global Trade LLC', 'SHELL_COMPANY', 'PAN', 'Panama City', 'Trading', SYSDATE-200, 'HIGH', 5000000, 'B2B');
-- Cust 4: Offshore Entity (Layering node 2)
INSERT INTO customers VALUES (4, 'Apex Holdings', 'BUSINESS', 'CYM', 'George Town', 'Investment', SYSDATE-300, 'HIGH', 10000000, 'Wealth');
-- Cust 5: Another Smurf
INSERT INTO customers VALUES (5, 'Charlie Brown', 'INDIVIDUAL', 'USA', 'New York', 'Contractor', SYSDATE-400, 'MEDIUM', 60000, 'Business');

-- Insert Accounts
INSERT INTO accounts VALUES (1001, 1, 'CHECKING', SYSDATE-1000, 'ACTIVE', 101, 'USD');
INSERT INTO accounts VALUES (1002, 2, 'CHECKING', SYSDATE-500, 'ACTIVE', 102, 'USD');
INSERT INTO accounts VALUES (1003, 3, 'WIRE', SYSDATE-200, 'ACTIVE', 102, 'USD');
INSERT INTO accounts VALUES (1004, 4, 'WIRE', SYSDATE-300, 'ACTIVE', 103, 'USD');
INSERT INTO accounts VALUES (1005, 5, 'CHECKING', SYSDATE-400, 'ACTIVE', 101, 'USD');

-- Insert Transactions
-- Normal Txns (Acc 1001)
INSERT INTO transactions VALUES (10001, 1001, 'CASH_DEPOSIT', 2500, 'USD', NULL, 'Self', SYSDATE-15, 'BRANCH', 101, 'Salary', 'USA', 'USA');
INSERT INTO transactions VALUES (10002, 1001, 'CASH_WITHDRAWAL', 300, 'USD', NULL, 'Self', SYSDATE-14, 'ATM', 101, 'Cash', 'USA', 'USA');

-- STRUCTURING Txns (Acc 1002 - Bob Jones, Smurf) - 4 deposits under 10k within 5 days totaling 37k
INSERT INTO transactions VALUES (10003, 1002, 'CASH_DEPOSIT', 9500, 'USD', NULL, 'Self', SYSDATE-6, 'BRANCH', 102, 'Sales', 'USA', 'USA');
INSERT INTO transactions VALUES (10004, 1002, 'CASH_DEPOSIT', 9200, 'USD', NULL, 'Self', SYSDATE-5, 'BRANCH', 102, 'Sales', 'USA', 'USA');
INSERT INTO transactions VALUES (10005, 1002, 'CASH_DEPOSIT', 9800, 'USD', NULL, 'Self', SYSDATE-4, 'BRANCH', 102, 'Sales', 'USA', 'USA');
INSERT INTO transactions VALUES (10006, 1002, 'CASH_DEPOSIT', 8500, 'USD', NULL, 'Self', SYSDATE-2, 'BRANCH', 102, 'Sales', 'USA', 'USA');

-- STRUCTURING Txns (Acc 1005 - Charlie Brown) - 3 deposits under 10k within 3 days
INSERT INTO transactions VALUES (10007, 1005, 'CASH_DEPOSIT', 9900, 'USD', NULL, 'Self', SYSDATE-10, 'BRANCH', 101, 'Contract', 'USA', 'USA');
INSERT INTO transactions VALUES (10008, 1005, 'CASH_DEPOSIT', 9900, 'USD', NULL, 'Self', SYSDATE-9, 'BRANCH', 101, 'Contract', 'USA', 'USA');
INSERT INTO transactions VALUES (10009, 1005, 'CASH_DEPOSIT', 9900, 'USD', NULL, 'Self', SYSDATE-8, 'BRANCH', 101, 'Contract', 'USA', 'USA');

-- FUND FLOW & LAYERING Txns
-- A -> B -> C -> D rapid movement
-- Step 1: External -> 1003 (Global Trade)
INSERT INTO transactions VALUES (10010, 1003, 'WIRE_IN', 250000, 'USD', 9999, 'Unknown Corp', SYSDATE-1, 'ONLINE', 102, 'Consulting', 'IRN', 'USA');
-- Step 2: 1003 -> 1004 (Apex Holdings) within 2 hours
INSERT INTO transactions VALUES (10011, 1003, 'WIRE_OUT', 248000, 'USD', 1004, 'Apex Holdings', SYSDATE-0.95, 'ONLINE', 102, 'Investment', 'USA', 'CYM');
-- Receiving side of Step 2
INSERT INTO transactions VALUES (10012, 1004, 'WIRE_IN', 248000, 'USD', 1003, 'Global Trade LLC', SYSDATE-0.95, 'ONLINE', 103, 'Investment', 'USA', 'CYM');
-- Step 3: 1004 -> External within 5 hours
INSERT INTO transactions VALUES (10013, 1004, 'WIRE_OUT', 245000, 'USD', 8888, 'Offshore Trust', SYSDATE-0.80, 'ONLINE', 103, 'Dividend', 'CYM', 'PAN');

-- Add some round amount transactions for risk scoring
INSERT INTO transactions VALUES (10014, 1003, 'WIRE_IN', 50000, 'USD', 7777, 'Corp A', SYSDATE-20, 'ONLINE', 102, 'Fees', 'USA', 'USA');
INSERT INTO transactions VALUES (10015, 1003, 'WIRE_IN', 100000, 'USD', 7778, 'Corp B', SYSDATE-19, 'ONLINE', 102, 'Fees', 'USA', 'USA');

COMMIT;
EXIT;
EOSQL

# 6. Pre-configure SQL Developer connection for the agent
echo "Configuring SQL Developer connection..."
ensure_hr_connection "AML Investigation" "aml_investigator" "AML2024Secure"

# 7. Start SQL Developer and wait for it
echo "Launching SQL Developer..."
su - ga -c "DISPLAY=:1 /opt/sqldeveloper/sqldeveloper.sh > /tmp/sqldeveloper.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "sql developer\|oracle sql"; then
        break
    fi
    sleep 1
done

# Maximize SQL Developer
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Try to automatically open the connection to save agent time
open_hr_connection_in_sqldeveloper

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== AML Task Setup Complete ==="