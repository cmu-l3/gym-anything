#!/bin/bash
# Setup script for OFAC Sanctions Fuzzy Screening task
echo "=== Setting up OFAC Sanctions Fuzzy Screening Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# 1. Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# 2. Clean up previous run artifacts
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER compliance_officer CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# 3. Create compliance_officer user
echo "Creating compliance_officer user..."
oracle_query "CREATE USER compliance_officer IDENTIFIED BY Trade2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO compliance_officer;
GRANT RESOURCE TO compliance_officer;
GRANT CREATE VIEW TO compliance_officer;
GRANT CREATE SESSION TO compliance_officer;
GRANT CREATE TABLE TO compliance_officer;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create compliance_officer user"
    exit 1
fi
echo "compliance_officer user created."

# 4. Create Tables and Insert Data
echo "Creating schema tables and populating OFAC/ERP data..."

sudo docker exec -i oracle-xe sqlplus -s compliance_officer/Trade2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- OFAC_SDN Table
CREATE TABLE OFAC_SDN (
    ent_num NUMBER PRIMARY KEY, 
    sdn_name VARCHAR2(350), 
    sdn_type VARCHAR2(12), 
    program VARCHAR2(50), 
    country VARCHAR2(250)
);

INSERT INTO OFAC_SDN VALUES (1, 'AEROFLOT RUSSIAN AIRLINES', 'Entity', 'RUSSIA-EO14024', 'Russia');
INSERT INTO OFAC_SDN VALUES (2, 'KIM JONG UN', 'Individual', 'DPRK', 'North Korea');
INSERT INTO OFAC_SDN VALUES (3, 'GAZPROM', 'Entity', 'RUSSIA-EO14024', 'Russia');
INSERT INTO OFAC_SDN VALUES (4, 'OSAMA BIN LADEN', 'Individual', 'SDGT', 'Unknown');
INSERT INTO OFAC_SDN VALUES (5, 'BANCO DE DESARROLLO ECON SOC VEN', 'Entity', 'VENEZUELA', 'Venezuela');

-- OFAC_ALT Table
CREATE TABLE OFAC_ALT (
    ent_num NUMBER, 
    alt_num NUMBER PRIMARY KEY, 
    alt_type VARCHAR2(15), 
    alt_name VARCHAR2(350),
    FOREIGN KEY (ent_num) REFERENCES OFAC_SDN(ent_num)
);

INSERT INTO OFAC_ALT VALUES (1, 101, 'a.k.a.', 'AEROFLOT AIRLINES');
INSERT INTO OFAC_ALT VALUES (4, 102, 'a.k.a.', 'USAMA BIN LADIN');
INSERT INTO OFAC_ALT VALUES (5, 103, 'a.k.a.', 'BANDES');

-- ERP_CUSTOMERS Table
CREATE TABLE ERP_CUSTOMERS (
    customer_id NUMBER PRIMARY KEY, 
    customer_name VARCHAR2(350), 
    country VARCHAR2(50), 
    account_manager VARCHAR2(100)
);

-- True Positives (Will score >= 88 JW Similarity)
INSERT INTO ERP_CUSTOMERS VALUES (10, 'AEROFLOT AIRLINES LLC', 'Russia', 'Bob');         -- Matches ALT (101)
INSERT INTO ERP_CUSTOMERS VALUES (11, 'KIM JONG-UN', 'China', 'Alice');                  -- Matches SDN (2)
INSERT INTO ERP_CUSTOMERS VALUES (12, 'GAZPROM INC', 'Russia', 'Charlie');               -- Matches SDN (3)
INSERT INTO ERP_CUSTOMERS VALUES (13, 'USAMA BIN LADEN TRADING', 'Pakistan', 'Dave');    -- Matches ALT (102)
INSERT INTO ERP_CUSTOMERS VALUES (14, 'BANDES BANK', 'Venezuela', 'Eve');                -- Matches ALT (103)
INSERT INTO ERP_CUSTOMERS VALUES (15, 'AEROFLOT RUSSIAN AIRWAYS', 'Russia', 'Frank');    -- Matches SDN (1)

-- True Negatives (Safe, will score < 88 JW Similarity)
INSERT INTO ERP_CUSTOMERS VALUES (20, 'WALMART STORES INC', 'USA', 'Grace');
INSERT INTO ERP_CUSTOMERS VALUES (21, 'TOYOTA MOTOR CORP', 'Japan', 'Heidi');
INSERT INTO ERP_CUSTOMERS VALUES (22, 'SAMSUNG ELECTRONICS', 'South Korea', 'Ivan');
INSERT INTO ERP_CUSTOMERS VALUES (23, 'JOHNSON AND JOHNSON', 'USA', 'Judy');

-- ERP_ORDERS Table
CREATE TABLE ERP_ORDERS (
    order_id NUMBER PRIMARY KEY, 
    customer_id NUMBER, 
    order_date DATE, 
    order_amount NUMBER(12,2), 
    status VARCHAR2(20),
    FOREIGN KEY (customer_id) REFERENCES ERP_CUSTOMERS(customer_id)
);

INSERT INTO ERP_ORDERS VALUES (1001, 10, SYSDATE-2, 50000.00, 'PENDING');
INSERT INTO ERP_ORDERS VALUES (1002, 11, SYSDATE-1, 12500.00, 'PENDING');
INSERT INTO ERP_ORDERS VALUES (1003, 12, SYSDATE-1, 875000.00, 'PENDING');
INSERT INTO ERP_ORDERS VALUES (1004, 13, SYSDATE-5, 4500.00, 'PENDING');
INSERT INTO ERP_ORDERS VALUES (1005, 14, SYSDATE-3, 99000.00, 'PENDING');
INSERT INTO ERP_ORDERS VALUES (1006, 15, SYSDATE-1, 32000.00, 'PENDING');
INSERT INTO ERP_ORDERS VALUES (1007, 20, SYSDATE-2, 14000.00, 'PENDING');
INSERT INTO ERP_ORDERS VALUES (1008, 21, SYSDATE-1, 22000.00, 'PENDING');
INSERT INTO ERP_ORDERS VALUES (1009, 22, SYSDATE-4, 11500.00, 'PENDING');
INSERT INTO ERP_ORDERS VALUES (1010, 23, SYSDATE-1, 8500.00, 'PENDING');

COMMIT;
EXIT;
EOSQL

echo "Data populated successfully."

# 5. Pre-configure SQL Developer connection for the agent
echo "Configuring SQL Developer connection..."
ensure_hr_connection "Trade Compliance" "compliance_officer" "Trade2024"

# 6. Take initial screenshot
echo "Taking initial screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="