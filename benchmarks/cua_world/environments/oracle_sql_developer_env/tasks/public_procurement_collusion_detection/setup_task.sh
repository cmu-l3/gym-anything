#!/bin/bash
echo "=== Setting up Public Procurement Collusion Detection Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /home/ga/.task_start_time

# Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# Clean up previous run artifacts
echo "Cleaning up..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER audit_mgr CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# Create user
echo "Creating AUDIT_MGR user..."
oracle_query "CREATE USER audit_mgr IDENTIFIED BY Audit2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO audit_mgr;
GRANT RESOURCE TO audit_mgr;
GRANT CREATE VIEW TO audit_mgr;
GRANT CREATE PROCEDURE TO audit_mgr;
GRANT CREATE SESSION TO audit_mgr;
GRANT CREATE TABLE TO audit_mgr;
EXIT;" "system"

# Create tables and insert data
echo "Creating tables and inserting data..."
sudo docker exec -i oracle-xe sqlplus -s audit_mgr/Audit2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE VENDORS (
    vendor_id NUMBER PRIMARY KEY,
    vendor_name VARCHAR2(100),
    tax_id VARCHAR2(20),
    address_line1 VARCHAR2(100),
    city VARCHAR2(50),
    state VARCHAR2(2),
    zip_code VARCHAR2(10),
    phone VARCHAR2(20),
    registration_date DATE
);

CREATE TABLE CONTRACT_CATEGORIES (
    category_id NUMBER PRIMARY KEY,
    category_name VARCHAR2(100),
    department VARCHAR2(100)
);

CREATE TABLE CONTRACTS (
    contract_id NUMBER PRIMARY KEY,
    category_id NUMBER,
    title VARCHAR2(200),
    award_date DATE,
    estimated_value NUMBER,
    status VARCHAR2(20)
);

CREATE TABLE BIDS (
    bid_id NUMBER PRIMARY KEY,
    contract_id NUMBER,
    vendor_id NUMBER,
    bid_amount NUMBER,
    bid_date DATE,
    is_winning_bid VARCHAR2(1)
);

-- Insert Vendors
-- V1 & V3 have shared addresses (when normalized). V1 & V2 have shared phone numbers.
INSERT INTO VENDORS VALUES (1, 'ABC Paving', '11-111', '123 Main Street, Suite 100', 'Cityville', 'ST', '12345', '555-0101', SYSDATE);
INSERT INTO VENDORS VALUES (2, 'XYZ Construction', '22-222', '456 Oak Road.', 'Cityville', 'ST', '12345', '555-0101', SYSDATE);
INSERT INTO VENDORS VALUES (3, 'Shell Corp', '33-333', '123 MAIN ST, STE 100', 'Cityville', 'ST', '12345', '555-0202', SYSDATE);
INSERT INTO VENDORS VALUES (4, 'Honest Builders', '44-444', '789 Pine Avenue', 'Cityville', 'ST', '12345', '555-0303', SYSDATE);
INSERT INTO VENDORS VALUES (5, 'ACME Concrete', '55-555', '321 Elm Boulevard', 'Cityville', 'ST', '12345', '555-0404', SYSDATE);
INSERT INTO VENDORS VALUES (6, 'Perfect Corp', '66-666', '999 Clean Drive', 'Cityville', 'ST', '12345', '555-0505', SYSDATE);

-- Non-colluding bulk vendors
INSERT INTO VENDORS VALUES (10, 'Sup 1', '71', '1', 'A', 'A', '1', '11', SYSDATE);
INSERT INTO VENDORS VALUES (11, 'Sup 2', '72', '2', 'A', 'A', '1', '22', SYSDATE);
INSERT INTO VENDORS VALUES (12, 'Sup 3', '73', '3', 'A', 'A', '1', '33', SYSDATE);
INSERT INTO VENDORS VALUES (13, 'Sup 4', '74', '4', 'A', 'A', '1', '44', SYSDATE);
INSERT INTO VENDORS VALUES (14, 'Sup 5', '75', '5', 'A', 'A', '1', '55', SYSDATE);

-- Categories
INSERT INTO CONTRACT_CATEGORIES VALUES (1, 'Asphalt Paving', 'Public Works');
INSERT INTO CONTRACT_CATEGORIES VALUES (2, 'General Construction', 'Facilities');
INSERT INTO CONTRACT_CATEGORIES VALUES (3, 'Electrical Services', 'Facilities');
INSERT INTO CONTRACT_CATEGORIES VALUES (4, 'Office Supplies', 'Administration');

-- Contracts
-- Category 1 (Highly concentrated, V1 dominates)
INSERT INTO CONTRACTS VALUES (101, 1, 'Paving A', SYSDATE-10, 100000, 'AWARDED');
INSERT INTO CONTRACTS VALUES (102, 1, 'Paving B', SYSDATE-20, 120000, 'AWARDED');
INSERT INTO CONTRACTS VALUES (103, 1, 'Paving C', SYSDATE-30, 110000, 'AWARDED');
INSERT INTO CONTRACTS VALUES (104, 1, 'Paving D', SYSDATE-40, 90000, 'AWARDED');

-- Category 2 (Highly concentrated, split between 3)
INSERT INTO CONTRACTS VALUES (201, 2, 'Build A', SYSDATE-10, 200000, 'AWARDED');
INSERT INTO CONTRACTS VALUES (202, 2, 'Build B', SYSDATE-20, 210000, 'AWARDED');
INSERT INTO CONTRACTS VALUES (203, 2, 'Build C', SYSDATE-30, 150000, 'AWARDED');

-- Category 3 (Highly concentrated, V4 wins all, V5 is complementary)
INSERT INTO CONTRACTS VALUES (301, 3, 'Elec A', SYSDATE-5, 100000, 'AWARDED');
INSERT INTO CONTRACTS VALUES (302, 3, 'Elec B', SYSDATE-6, 150000, 'AWARDED');
INSERT INTO CONTRACTS VALUES (303, 3, 'Elec C', SYSDATE-7, 200000, 'AWARDED');

-- Category 4 (Low concentration, 5 distinct winners)
INSERT INTO CONTRACTS VALUES (401, 4, 'Sup A', SYSDATE-1, 10000, 'AWARDED');
INSERT INTO CONTRACTS VALUES (402, 4, 'Sup B', SYSDATE-2, 10000, 'AWARDED');
INSERT INTO CONTRACTS VALUES (403, 4, 'Sup C', SYSDATE-3, 10000, 'AWARDED');
INSERT INTO CONTRACTS VALUES (404, 4, 'Sup D', SYSDATE-4, 10000, 'AWARDED');
INSERT INTO CONTRACTS VALUES (405, 4, 'Sup E', SYSDATE-5, 10000, 'AWARDED');

-- Bids
-- C1: V1 wins 3 (75%), V5 wins 1 (25%) -> HHI = 6250
INSERT INTO BIDS VALUES (1, 101, 1, 95000, SYSDATE-12, 'Y');
INSERT INTO BIDS VALUES (2, 102, 1, 115000, SYSDATE-22, 'Y');
INSERT INTO BIDS VALUES (3, 103, 1, 105000, SYSDATE-32, 'Y');
INSERT INTO BIDS VALUES (4, 104, 5, 85000, SYSDATE-42, 'Y');

-- C2: V2 wins 1, V4 wins 1, V6 wins 1 -> HHI = 3333.33
INSERT INTO BIDS VALUES (5, 201, 2, 190000, SYSDATE-12, 'Y');
INSERT INTO BIDS VALUES (6, 202, 4, 205000, SYSDATE-22, 'Y');
INSERT INTO BIDS VALUES (7, 203, 6, 145000, SYSDATE-32, 'Y');

-- C3: Complementary bids. V4 wins all (HHI 10000). V5 bids within 5%.
INSERT INTO BIDS VALUES (8, 301, 4, 100000, SYSDATE-6, 'Y');
INSERT INTO BIDS VALUES (9, 301, 5, 104000, SYSDATE-6, 'N'); -- 4% margin

INSERT INTO BIDS VALUES (10, 302, 4, 150000, SYSDATE-7, 'Y');
INSERT INTO BIDS VALUES (11, 302, 5, 155000, SYSDATE-7, 'N'); -- 3.33% margin

INSERT INTO BIDS VALUES (12, 303, 4, 200000, SYSDATE-8, 'Y');
INSERT INTO BIDS VALUES (13, 303, 5, 210000, SYSDATE-8, 'N'); -- 5% margin

-- C4: Low concentration. 5 vendors win 1 each (20% share). HHI = 2000.
INSERT INTO BIDS VALUES (14, 401, 10, 9000, SYSDATE-2, 'Y');
INSERT INTO BIDS VALUES (15, 402, 11, 9000, SYSDATE-3, 'Y');
INSERT INTO BIDS VALUES (16, 403, 12, 9000, SYSDATE-4, 'Y');
INSERT INTO BIDS VALUES (17, 404, 13, 9000, SYSDATE-5, 'Y');
INSERT INTO BIDS VALUES (18, 405, 14, 9000, SYSDATE-6, 'Y');

COMMIT;
EXIT;
EOSQL

echo "Data populated successfully."

# Setup export directory
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents

# Configure SQL Developer Connection
ensure_hr_connection "Audit Database" "audit_mgr" "Audit2024"
open_hr_connection_in_sqldeveloper

# Take screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="