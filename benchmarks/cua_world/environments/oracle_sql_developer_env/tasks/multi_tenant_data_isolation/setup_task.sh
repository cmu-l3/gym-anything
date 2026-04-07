#!/bin/bash
# Setup script for Multi-Tenant VPD Data Isolation task
echo "=== Setting up Multi-Tenant VPD Data Isolation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# -------------------------------------------------------
# Verify Oracle container is running
# -------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# -------------------------------------------------------
# Clean up previous run artifacts
# -------------------------------------------------------
echo "Cleaning up previous run artifacts..."

# Drop VPD policies first (must be done before dropping tables/users)
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
SET SERVEROUTPUT ON
BEGIN
  BEGIN
    DBMS_RLS.DROP_POLICY(
      object_schema   => 'SAAS_ADMIN',
      object_name     => 'CUSTOMER_DATA',
      policy_name     => 'CUSTOMER_TENANT_POLICY'
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    DBMS_RLS.DROP_POLICY(
      object_schema   => 'SAAS_ADMIN',
      object_name     => 'FINANCIAL_RECORDS',
      policy_name     => 'FINANCIAL_TENANT_POLICY'
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
/
EXIT;
EOSQL

# Drop tenant users if they exist
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
BEGIN
  FOR u IN (SELECT username FROM dba_users WHERE username IN ('TENANT1_USER','TENANT2_USER','TENANT3_USER','SAAS_ADMIN')) LOOP
    EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
  END LOOP;
END;
/
EXIT;
EOSQL

# Drop context if it exists
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
BEGIN
  EXECUTE IMMEDIATE 'DROP CONTEXT TENANT_CTX';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;
EOSQL

echo "Cleanup complete."

# -------------------------------------------------------
# Step 3: Create the SAAS_ADMIN user (SAAS_PLATFORM schema)
# -------------------------------------------------------
echo "Creating SAAS_ADMIN user..."
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
CREATE USER saas_admin IDENTIFIED BY "SaaS2024"
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON USERS;

GRANT CONNECT TO saas_admin;
GRANT RESOURCE TO saas_admin;
GRANT CREATE VIEW TO saas_admin;
GRANT CREATE PROCEDURE TO saas_admin;
GRANT CREATE SESSION TO saas_admin;
GRANT CREATE ANY CONTEXT TO saas_admin;
GRANT EXEMPT ACCESS POLICY TO saas_admin;
GRANT CREATE ANY TRIGGER TO saas_admin;
GRANT EXECUTE ON DBMS_RLS TO saas_admin;
GRANT EXECUTE ON DBMS_SESSION TO saas_admin;
EXIT;
EOSQL

echo "SAAS_ADMIN user created with required privileges."

# -------------------------------------------------------
# Step 5: Create tenant users
# -------------------------------------------------------
echo "Creating tenant users..."
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
CREATE USER tenant1_user IDENTIFIED BY "Tenant1Pass"
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP;
GRANT CONNECT TO tenant1_user;
GRANT CREATE SESSION TO tenant1_user;

CREATE USER tenant2_user IDENTIFIED BY "Tenant2Pass"
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP;
GRANT CONNECT TO tenant2_user;
GRANT CREATE SESSION TO tenant2_user;

CREATE USER tenant3_user IDENTIFIED BY "Tenant3Pass"
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP;
GRANT CONNECT TO tenant3_user;
GRANT CREATE SESSION TO tenant3_user;
EXIT;
EOSQL

echo "Tenant users created."

# -------------------------------------------------------
# Step 6: Create tables under SAAS_ADMIN schema
# -------------------------------------------------------
echo "Creating SAAS_PLATFORM tables..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
-- TENANTS table
CREATE TABLE TENANTS (
    tenant_id     NUMBER PRIMARY KEY,
    tenant_name   VARCHAR2(100) NOT NULL,
    subdomain     VARCHAR2(50) NOT NULL,
    plan_tier     VARCHAR2(20) NOT NULL,
    created_date  DATE DEFAULT SYSDATE,
    is_active     NUMBER(1) DEFAULT 1
);

-- CUSTOMER_DATA table
CREATE TABLE CUSTOMER_DATA (
    record_id      NUMBER PRIMARY KEY,
    tenant_id      NUMBER REFERENCES TENANTS(tenant_id),
    customer_name  VARCHAR2(200) NOT NULL,
    email          VARCHAR2(200),
    phone          VARCHAR2(50),
    address        VARCHAR2(500),
    created_date   DATE DEFAULT SYSDATE
);

-- FINANCIAL_RECORDS table
CREATE TABLE FINANCIAL_RECORDS (
    record_id         NUMBER PRIMARY KEY,
    tenant_id         NUMBER REFERENCES TENANTS(tenant_id),
    transaction_type  VARCHAR2(50) NOT NULL,
    amount            NUMBER(15,2) NOT NULL,
    currency          VARCHAR2(3) DEFAULT 'USD',
    description       VARCHAR2(500),
    transaction_date  DATE DEFAULT SYSDATE,
    invoice_number    VARCHAR2(50)
);

-- API_KEYS table
CREATE TABLE API_KEYS (
    key_id       NUMBER PRIMARY KEY,
    tenant_id    NUMBER REFERENCES TENANTS(tenant_id),
    api_key      VARCHAR2(64) NOT NULL,
    key_name     VARCHAR2(100),
    permissions  VARCHAR2(500),
    created_date DATE DEFAULT SYSDATE,
    is_active    NUMBER(1) DEFAULT 1
);

-- USER_SESSIONS table
CREATE TABLE USER_SESSIONS (
    session_id   NUMBER PRIMARY KEY,
    tenant_id    NUMBER REFERENCES TENANTS(tenant_id),
    user_email   VARCHAR2(200),
    login_time   TIMESTAMP DEFAULT SYSTIMESTAMP,
    logout_time  TIMESTAMP,
    ip_address   VARCHAR2(45)
);

EXIT;
EOSQL

echo "Tables created."

# -------------------------------------------------------
# Step 13: Create sequences for IDs
# -------------------------------------------------------
echo "Creating sequences..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
CREATE SEQUENCE CUSTOMER_SEQ START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE FINANCIAL_SEQ START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE APIKEY_SEQ START WITH 100 INCREMENT BY 1;
CREATE SEQUENCE SESSION_SEQ START WITH 100 INCREMENT BY 1;
EXIT;
EOSQL

echo "Sequences created."

# -------------------------------------------------------
# Step 7: Insert realistic SaaS platform data
# -------------------------------------------------------
echo "Inserting tenant data..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
-- Insert tenants
INSERT INTO TENANTS VALUES (1, 'Acme Corp', 'acme', 'ENTERPRISE', DATE '2022-03-15', 1);
INSERT INTO TENANTS VALUES (2, 'GlobalTech Inc', 'globaltech', 'PROFESSIONAL', DATE '2022-07-22', 1);
INSERT INTO TENANTS VALUES (3, 'StartupXYZ', 'startupxyz', 'STARTER', DATE '2023-01-10', 1);
COMMIT;
EXIT;
EOSQL

# --- Tenant 1: Acme Corp - 15 customer records ---
echo "Inserting Acme Corp (Tenant 1) customer data..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
INSERT INTO CUSTOMER_DATA VALUES (1, 1, 'John Mitchell', 'john.mitchell@acmecorp.com', '+1-415-555-0101', '123 Market St, San Francisco, CA 94105', DATE '2023-01-15');
INSERT INTO CUSTOMER_DATA VALUES (2, 1, 'Sarah Johnson', 'sarah.j@acmecorp.com', '+1-415-555-0102', '456 Pine Ave, San Francisco, CA 94108', DATE '2023-02-20');
INSERT INTO CUSTOMER_DATA VALUES (3, 1, 'Michael Chen', 'mchen@acmecorp.com', '+1-650-555-0103', '789 Oak Blvd, Palo Alto, CA 94301', DATE '2023-03-10');
INSERT INTO CUSTOMER_DATA VALUES (4, 1, 'Emily Rodriguez', 'e.rodriguez@acmecorp.com', '+1-408-555-0104', '321 Elm St, San Jose, CA 95110', DATE '2023-03-25');
INSERT INTO CUSTOMER_DATA VALUES (5, 1, 'David Park', 'dpark@acmecorp.com', '+1-510-555-0105', '654 Cedar Dr, Oakland, CA 94612', DATE '2023-04-12');
INSERT INTO CUSTOMER_DATA VALUES (6, 1, 'Lisa Thompson', 'lisa.t@acmecorp.com', '+1-415-555-0106', '987 Birch Ln, San Francisco, CA 94110', DATE '2023-05-01');
INSERT INTO CUSTOMER_DATA VALUES (7, 1, 'Robert Kim', 'rkim@acmecorp.com', '+1-650-555-0107', '147 Maple Ct, Mountain View, CA 94040', DATE '2023-05-18');
INSERT INTO CUSTOMER_DATA VALUES (8, 1, 'Jennifer Davis', 'jdavis@acmecorp.com', '+1-408-555-0108', '258 Walnut Way, Sunnyvale, CA 94086', DATE '2023-06-03');
INSERT INTO CUSTOMER_DATA VALUES (9, 1, 'Christopher Lee', 'clee@acmecorp.com', '+1-415-555-0109', '369 Spruce St, San Francisco, CA 94115', DATE '2023-06-22');
INSERT INTO CUSTOMER_DATA VALUES (10, 1, 'Amanda Wilson', 'awilson@acmecorp.com', '+1-510-555-0110', '741 Redwood Ave, Berkeley, CA 94704', DATE '2023-07-08');
INSERT INTO CUSTOMER_DATA VALUES (11, 1, 'James Martinez', 'jmartinez@acmecorp.com', '+1-650-555-0111', '852 Sequoia Rd, Menlo Park, CA 94025', DATE '2023-07-30');
INSERT INTO CUSTOMER_DATA VALUES (12, 1, 'Patricia Brown', 'pbrown@acmecorp.com', '+1-408-555-0112', '963 Willow Pl, Santa Clara, CA 95050', DATE '2023-08-15');
INSERT INTO CUSTOMER_DATA VALUES (13, 1, 'Daniel Taylor', 'dtaylor@acmecorp.com', '+1-415-555-0113', '174 Cypress Blvd, San Francisco, CA 94102', DATE '2023-09-02');
INSERT INTO CUSTOMER_DATA VALUES (14, 1, 'Michelle White', 'mwhite@acmecorp.com', '+1-650-555-0114', '285 Juniper Ln, Redwood City, CA 94063', DATE '2023-09-20');
INSERT INTO CUSTOMER_DATA VALUES (15, 1, 'Thomas Anderson', 'tanderson@acmecorp.com', '+1-510-555-0115', '396 Magnolia Dr, Fremont, CA 94538', DATE '2023-10-05');
COMMIT;
EXIT;
EOSQL

# --- Tenant 2: GlobalTech Inc - 12 customer records ---
echo "Inserting GlobalTech Inc (Tenant 2) customer data..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
INSERT INTO CUSTOMER_DATA VALUES (16, 2, 'Alexander Petrov', 'apetrov@globaltech.io', '+1-212-555-0201', '100 Broadway, New York, NY 10005', DATE '2023-02-01');
INSERT INTO CUSTOMER_DATA VALUES (17, 2, 'Maria Gonzalez', 'mgonzalez@globaltech.io', '+1-212-555-0202', '200 Wall St, New York, NY 10006', DATE '2023-02-18');
INSERT INTO CUSTOMER_DATA VALUES (18, 2, 'William Turner', 'wturner@globaltech.io', '+1-718-555-0203', '300 Atlantic Ave, Brooklyn, NY 11201', DATE '2023-03-05');
INSERT INTO CUSTOMER_DATA VALUES (19, 2, 'Sophia Nakamura', 'snakamura@globaltech.io', '+1-212-555-0204', '400 Park Ave, New York, NY 10022', DATE '2023-04-10');
INSERT INTO CUSTOMER_DATA VALUES (20, 2, 'Benjamin O''Brien', 'bobrien@globaltech.io', '+1-201-555-0205', '500 River Rd, Hoboken, NJ 07030', DATE '2023-04-28');
INSERT INTO CUSTOMER_DATA VALUES (21, 2, 'Olivia Schmidt', 'oschmidt@globaltech.io', '+1-212-555-0206', '600 Madison Ave, New York, NY 10065', DATE '2023-05-15');
INSERT INTO CUSTOMER_DATA VALUES (22, 2, 'Ethan Patel', 'epatel@globaltech.io', '+1-718-555-0207', '700 Flatbush Ave, Brooklyn, NY 11225', DATE '2023-06-01');
INSERT INTO CUSTOMER_DATA VALUES (23, 2, 'Isabella Rossi', 'irossi@globaltech.io', '+1-212-555-0208', '800 Lexington Ave, New York, NY 10065', DATE '2023-06-20');
INSERT INTO CUSTOMER_DATA VALUES (24, 2, 'Nathan Wright', 'nwright@globaltech.io', '+1-201-555-0209', '900 Washington St, Hoboken, NJ 07030', DATE '2023-07-10');
INSERT INTO CUSTOMER_DATA VALUES (25, 2, 'Emma Kowalski', 'ekowalski@globaltech.io', '+1-212-555-0210', '1010 5th Ave, New York, NY 10028', DATE '2023-08-01');
INSERT INTO CUSTOMER_DATA VALUES (26, 2, 'Lucas Fernandez', 'lfernandez@globaltech.io', '+1-718-555-0211', '1111 Ocean Pkwy, Brooklyn, NY 11230', DATE '2023-08-22');
INSERT INTO CUSTOMER_DATA VALUES (27, 2, 'Charlotte Dubois', 'cdubois@globaltech.io', '+1-212-555-0212', '1212 Amsterdam Ave, New York, NY 10027', DATE '2023-09-10');
COMMIT;
EXIT;
EOSQL

# --- Tenant 3: StartupXYZ - 8 customer records ---
echo "Inserting StartupXYZ (Tenant 3) customer data..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
INSERT INTO CUSTOMER_DATA VALUES (28, 3, 'Ryan Cooper', 'rcooper@startupxyz.co', '+1-512-555-0301', '100 Congress Ave, Austin, TX 78701', DATE '2023-03-01');
INSERT INTO CUSTOMER_DATA VALUES (29, 3, 'Ashley Morgan', 'amorgan@startupxyz.co', '+1-512-555-0302', '200 S Lamar Blvd, Austin, TX 78704', DATE '2023-03-20');
INSERT INTO CUSTOMER_DATA VALUES (30, 3, 'Kevin Huang', 'khuang@startupxyz.co', '+1-737-555-0303', '300 E 6th St, Austin, TX 78701', DATE '2023-04-15');
INSERT INTO CUSTOMER_DATA VALUES (31, 3, 'Nicole Foster', 'nfoster@startupxyz.co', '+1-512-555-0304', '400 W 2nd St, Austin, TX 78701', DATE '2023-05-10');
INSERT INTO CUSTOMER_DATA VALUES (32, 3, 'Brandon Rivera', 'brivera@startupxyz.co', '+1-737-555-0305', '500 Barton Springs Rd, Austin, TX 78704', DATE '2023-06-05');
INSERT INTO CUSTOMER_DATA VALUES (33, 3, 'Stephanie Cole', 'scole@startupxyz.co', '+1-512-555-0306', '600 Guadalupe St, Austin, TX 78701', DATE '2023-07-01');
INSERT INTO CUSTOMER_DATA VALUES (34, 3, 'Andrew Nguyen', 'anguyen@startupxyz.co', '+1-737-555-0307', '700 E Riverside Dr, Austin, TX 78741', DATE '2023-08-10');
INSERT INTO CUSTOMER_DATA VALUES (35, 3, 'Rachel Bennett', 'rbennett@startupxyz.co', '+1-512-555-0308', '800 Red River St, Austin, TX 78701', DATE '2023-09-01');
COMMIT;
EXIT;
EOSQL

# --- Tenant 1: Acme Corp - 20 financial records ---
echo "Inserting Acme Corp (Tenant 1) financial records..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
INSERT INTO FINANCIAL_RECORDS VALUES (1, 1, 'INVOICE', 15000.00, 'USD', 'Enterprise license Q1 2024', DATE '2024-01-05', 'INV-ACME-2024-001');
INSERT INTO FINANCIAL_RECORDS VALUES (2, 1, 'PAYMENT', 15000.00, 'USD', 'Payment for INV-ACME-2024-001', DATE '2024-01-15', 'PAY-ACME-2024-001');
INSERT INTO FINANCIAL_RECORDS VALUES (3, 1, 'INVOICE', 3500.00, 'USD', 'Additional user licenses x10', DATE '2024-01-20', 'INV-ACME-2024-002');
INSERT INTO FINANCIAL_RECORDS VALUES (4, 1, 'INVOICE', 8750.00, 'USD', 'Custom integration setup', DATE '2024-02-01', 'INV-ACME-2024-003');
INSERT INTO FINANCIAL_RECORDS VALUES (5, 1, 'PAYMENT', 3500.00, 'USD', 'Payment for INV-ACME-2024-002', DATE '2024-02-10', 'PAY-ACME-2024-002');
INSERT INTO FINANCIAL_RECORDS VALUES (6, 1, 'REFUND', 1200.00, 'USD', 'Partial refund unused API calls', DATE '2024-02-15', 'REF-ACME-2024-001');
INSERT INTO FINANCIAL_RECORDS VALUES (7, 1, 'INVOICE', 15000.00, 'USD', 'Enterprise license Q2 2024', DATE '2024-04-01', 'INV-ACME-2024-004');
INSERT INTO FINANCIAL_RECORDS VALUES (8, 1, 'PAYMENT', 8750.00, 'USD', 'Payment for INV-ACME-2024-003', DATE '2024-04-05', 'PAY-ACME-2024-003');
INSERT INTO FINANCIAL_RECORDS VALUES (9, 1, 'INVOICE', 2200.00, 'USD', 'Premium support package monthly', DATE '2024-04-10', 'INV-ACME-2024-005');
INSERT INTO FINANCIAL_RECORDS VALUES (10, 1, 'PAYMENT', 15000.00, 'USD', 'Payment for INV-ACME-2024-004', DATE '2024-04-15', 'PAY-ACME-2024-004');
COMMIT;
EXIT;
EOSQL

sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
INSERT INTO FINANCIAL_RECORDS VALUES (11, 1, 'INVOICE', 5600.00, 'USD', 'Data migration services', DATE '2024-05-01', 'INV-ACME-2024-006');
INSERT INTO FINANCIAL_RECORDS VALUES (12, 1, 'PAYMENT', 2200.00, 'USD', 'Payment for INV-ACME-2024-005', DATE '2024-05-05', 'PAY-ACME-2024-005');
INSERT INTO FINANCIAL_RECORDS VALUES (13, 1, 'INVOICE', 950.00, 'USD', 'Training session - 5 users', DATE '2024-05-15', 'INV-ACME-2024-007');
INSERT INTO FINANCIAL_RECORDS VALUES (14, 1, 'PAYMENT', 5600.00, 'USD', 'Payment for INV-ACME-2024-006', DATE '2024-05-20', 'PAY-ACME-2024-006');
INSERT INTO FINANCIAL_RECORDS VALUES (15, 1, 'INVOICE', 15000.00, 'USD', 'Enterprise license Q3 2024', DATE '2024-07-01', 'INV-ACME-2024-008');
INSERT INTO FINANCIAL_RECORDS VALUES (16, 1, 'PAYMENT', 950.00, 'USD', 'Payment for INV-ACME-2024-007', DATE '2024-07-05', 'PAY-ACME-2024-007');
INSERT INTO FINANCIAL_RECORDS VALUES (17, 1, 'INVOICE', 4200.00, 'USD', 'API overage charges June', DATE '2024-07-10', 'INV-ACME-2024-009');
INSERT INTO FINANCIAL_RECORDS VALUES (18, 1, 'PAYMENT', 15000.00, 'USD', 'Payment for INV-ACME-2024-008', DATE '2024-07-15', 'PAY-ACME-2024-008');
INSERT INTO FINANCIAL_RECORDS VALUES (19, 1, 'CREDIT', 500.00, 'USD', 'Loyalty credit annual renewal', DATE '2024-07-20', 'CRD-ACME-2024-001');
INSERT INTO FINANCIAL_RECORDS VALUES (20, 1, 'PAYMENT', 4200.00, 'USD', 'Payment for INV-ACME-2024-009', DATE '2024-08-01', 'PAY-ACME-2024-009');
COMMIT;
EXIT;
EOSQL

# --- Tenant 2: GlobalTech Inc - 18 financial records ---
echo "Inserting GlobalTech Inc (Tenant 2) financial records..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
INSERT INTO FINANCIAL_RECORDS VALUES (21, 2, 'INVOICE', 7500.00, 'USD', 'Professional license Q1 2024', DATE '2024-01-03', 'INV-GT-2024-001');
INSERT INTO FINANCIAL_RECORDS VALUES (22, 2, 'PAYMENT', 7500.00, 'USD', 'Payment for INV-GT-2024-001', DATE '2024-01-12', 'PAY-GT-2024-001');
INSERT INTO FINANCIAL_RECORDS VALUES (23, 2, 'INVOICE', 1800.00, 'USD', 'Additional storage 500GB', DATE '2024-01-25', 'INV-GT-2024-002');
INSERT INTO FINANCIAL_RECORDS VALUES (24, 2, 'PAYMENT', 1800.00, 'USD', 'Payment for INV-GT-2024-002', DATE '2024-02-05', 'PAY-GT-2024-002');
INSERT INTO FINANCIAL_RECORDS VALUES (25, 2, 'INVOICE', 2400.00, 'USD', 'SSO integration module', DATE '2024-02-20', 'INV-GT-2024-003');
INSERT INTO FINANCIAL_RECORDS VALUES (26, 2, 'INVOICE', 7500.00, 'USD', 'Professional license Q2 2024', DATE '2024-04-01', 'INV-GT-2024-004');
INSERT INTO FINANCIAL_RECORDS VALUES (27, 2, 'PAYMENT', 2400.00, 'USD', 'Payment for INV-GT-2024-003', DATE '2024-04-08', 'PAY-GT-2024-003');
INSERT INTO FINANCIAL_RECORDS VALUES (28, 2, 'PAYMENT', 7500.00, 'USD', 'Payment for INV-GT-2024-004', DATE '2024-04-12', 'PAY-GT-2024-004');
INSERT INTO FINANCIAL_RECORDS VALUES (29, 2, 'INVOICE', 3200.00, 'USD', 'Custom reporting dashboard', DATE '2024-05-01', 'INV-GT-2024-005');
COMMIT;
EXIT;
EOSQL

sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
INSERT INTO FINANCIAL_RECORDS VALUES (30, 2, 'REFUND', 800.00, 'USD', 'Refund overcharged storage', DATE '2024-05-10', 'REF-GT-2024-001');
INSERT INTO FINANCIAL_RECORDS VALUES (31, 2, 'PAYMENT', 3200.00, 'USD', 'Payment for INV-GT-2024-005', DATE '2024-05-15', 'PAY-GT-2024-005');
INSERT INTO FINANCIAL_RECORDS VALUES (32, 2, 'INVOICE', 7500.00, 'USD', 'Professional license Q3 2024', DATE '2024-07-01', 'INV-GT-2024-006');
INSERT INTO FINANCIAL_RECORDS VALUES (33, 2, 'PAYMENT', 7500.00, 'USD', 'Payment for INV-GT-2024-006', DATE '2024-07-10', 'PAY-GT-2024-006');
INSERT INTO FINANCIAL_RECORDS VALUES (34, 2, 'INVOICE', 1500.00, 'USD', 'API access tier upgrade', DATE '2024-07-20', 'INV-GT-2024-007');
INSERT INTO FINANCIAL_RECORDS VALUES (35, 2, 'INVOICE', 4800.00, 'USD', 'Compliance audit module', DATE '2024-08-01', 'INV-GT-2024-008');
INSERT INTO FINANCIAL_RECORDS VALUES (36, 2, 'PAYMENT', 1500.00, 'USD', 'Payment for INV-GT-2024-007', DATE '2024-08-05', 'PAY-GT-2024-007');
INSERT INTO FINANCIAL_RECORDS VALUES (37, 2, 'INVOICE', 950.00, 'USD', 'Training session - 3 users', DATE '2024-08-15', 'INV-GT-2024-009');
INSERT INTO FINANCIAL_RECORDS VALUES (38, 2, 'PAYMENT', 4800.00, 'USD', 'Payment for INV-GT-2024-008', DATE '2024-08-20', 'PAY-GT-2024-009');
COMMIT;
EXIT;
EOSQL

# --- Tenant 3: StartupXYZ - 10 financial records ---
echo "Inserting StartupXYZ (Tenant 3) financial records..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
INSERT INTO FINANCIAL_RECORDS VALUES (39, 3, 'INVOICE', 1200.00, 'USD', 'Starter license Q1 2024', DATE '2024-01-08', 'INV-SX-2024-001');
INSERT INTO FINANCIAL_RECORDS VALUES (40, 3, 'PAYMENT', 1200.00, 'USD', 'Payment for INV-SX-2024-001', DATE '2024-01-18', 'PAY-SX-2024-001');
INSERT INTO FINANCIAL_RECORDS VALUES (41, 3, 'INVOICE', 350.00, 'USD', 'Additional user license x2', DATE '2024-02-10', 'INV-SX-2024-002');
INSERT INTO FINANCIAL_RECORDS VALUES (42, 3, 'PAYMENT', 350.00, 'USD', 'Payment for INV-SX-2024-002', DATE '2024-02-20', 'PAY-SX-2024-002');
INSERT INTO FINANCIAL_RECORDS VALUES (43, 3, 'INVOICE', 1200.00, 'USD', 'Starter license Q2 2024', DATE '2024-04-01', 'INV-SX-2024-003');
INSERT INTO FINANCIAL_RECORDS VALUES (44, 3, 'PAYMENT', 1200.00, 'USD', 'Payment for INV-SX-2024-003', DATE '2024-04-10', 'PAY-SX-2024-003');
INSERT INTO FINANCIAL_RECORDS VALUES (45, 3, 'INVOICE', 500.00, 'USD', 'Email notification addon', DATE '2024-05-05', 'INV-SX-2024-004');
INSERT INTO FINANCIAL_RECORDS VALUES (46, 3, 'PAYMENT', 500.00, 'USD', 'Payment for INV-SX-2024-004', DATE '2024-05-15', 'PAY-SX-2024-004');
INSERT INTO FINANCIAL_RECORDS VALUES (47, 3, 'INVOICE', 1200.00, 'USD', 'Starter license Q3 2024', DATE '2024-07-01', 'INV-SX-2024-005');
INSERT INTO FINANCIAL_RECORDS VALUES (48, 3, 'PAYMENT', 1200.00, 'USD', 'Payment for INV-SX-2024-005', DATE '2024-07-12', 'PAY-SX-2024-005');
COMMIT;
EXIT;
EOSQL

# --- API Keys for all tenants ---
echo "Inserting API keys..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
-- Tenant 1: Acme Corp - 3 API keys
INSERT INTO API_KEYS VALUES (1, 1, 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2', 'Production API Key', 'READ,WRITE,DELETE', DATE '2023-06-01', 1);
INSERT INTO API_KEYS VALUES (2, 1, 'f1e2d3c4b5a6f7e8d9c0b1a2f3e4d5c6b7a8f9e0d1c2b3a4f5e6d7c8b9a0f1e2', 'Staging API Key', 'READ,WRITE', DATE '2023-06-15', 1);
INSERT INTO API_KEYS VALUES (3, 1, '1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b', 'Analytics Read-Only Key', 'READ', DATE '2023-08-01', 1);

-- Tenant 2: GlobalTech Inc - 2 API keys
INSERT INTO API_KEYS VALUES (4, 2, 'b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3', 'Main Integration Key', 'READ,WRITE', DATE '2023-08-10', 1);
INSERT INTO API_KEYS VALUES (5, 2, 'c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4', 'Webhook Receiver Key', 'READ', DATE '2023-09-01', 1);

-- Tenant 3: StartupXYZ - 1 API key
INSERT INTO API_KEYS VALUES (6, 3, 'd4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5', 'Development API Key', 'READ,WRITE', DATE '2023-10-01', 1);
COMMIT;
EXIT;
EOSQL

# --- User Sessions for all tenants ---
echo "Inserting user sessions..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
-- Tenant 1: Acme Corp - 10 sessions
INSERT INTO USER_SESSIONS VALUES (1, 1, 'john.mitchell@acmecorp.com', TIMESTAMP '2024-08-01 08:30:00', TIMESTAMP '2024-08-01 17:45:00', '192.168.1.10');
INSERT INTO USER_SESSIONS VALUES (2, 1, 'sarah.j@acmecorp.com', TIMESTAMP '2024-08-01 09:15:00', TIMESTAMP '2024-08-01 16:30:00', '192.168.1.11');
INSERT INTO USER_SESSIONS VALUES (3, 1, 'mchen@acmecorp.com', TIMESTAMP '2024-08-02 07:45:00', TIMESTAMP '2024-08-02 18:00:00', '10.0.0.55');
INSERT INTO USER_SESSIONS VALUES (4, 1, 'e.rodriguez@acmecorp.com', TIMESTAMP '2024-08-02 10:00:00', TIMESTAMP '2024-08-02 15:30:00', '172.16.0.22');
INSERT INTO USER_SESSIONS VALUES (5, 1, 'dpark@acmecorp.com', TIMESTAMP '2024-08-03 08:00:00', TIMESTAMP '2024-08-03 17:00:00', '192.168.1.15');
INSERT INTO USER_SESSIONS VALUES (6, 1, 'lisa.t@acmecorp.com', TIMESTAMP '2024-08-03 09:30:00', TIMESTAMP '2024-08-03 16:45:00', '10.0.0.101');
INSERT INTO USER_SESSIONS VALUES (7, 1, 'rkim@acmecorp.com', TIMESTAMP '2024-08-04 08:15:00', TIMESTAMP '2024-08-04 17:30:00', '192.168.2.33');
INSERT INTO USER_SESSIONS VALUES (8, 1, 'jdavis@acmecorp.com', TIMESTAMP '2024-08-04 11:00:00', NULL, '172.16.1.44');
INSERT INTO USER_SESSIONS VALUES (9, 1, 'clee@acmecorp.com', TIMESTAMP '2024-08-05 07:30:00', TIMESTAMP '2024-08-05 16:00:00', '192.168.1.20');
INSERT INTO USER_SESSIONS VALUES (10, 1, 'awilson@acmecorp.com', TIMESTAMP '2024-08-05 09:45:00', TIMESTAMP '2024-08-05 18:15:00', '10.0.0.77');

-- Tenant 2: GlobalTech Inc - 8 sessions
INSERT INTO USER_SESSIONS VALUES (11, 2, 'apetrov@globaltech.io', TIMESTAMP '2024-08-01 09:00:00', TIMESTAMP '2024-08-01 18:00:00', '10.10.0.50');
INSERT INTO USER_SESSIONS VALUES (12, 2, 'mgonzalez@globaltech.io', TIMESTAMP '2024-08-01 08:45:00', TIMESTAMP '2024-08-01 17:30:00', '10.10.0.51');
INSERT INTO USER_SESSIONS VALUES (13, 2, 'wturner@globaltech.io', TIMESTAMP '2024-08-02 10:15:00', TIMESTAMP '2024-08-02 16:45:00', '10.10.1.22');
INSERT INTO USER_SESSIONS VALUES (14, 2, 'snakamura@globaltech.io', TIMESTAMP '2024-08-02 07:30:00', TIMESTAMP '2024-08-02 19:00:00', '10.10.0.55');
INSERT INTO USER_SESSIONS VALUES (15, 2, 'bobrien@globaltech.io', TIMESTAMP '2024-08-03 09:00:00', TIMESTAMP '2024-08-03 17:15:00', '10.10.2.10');
INSERT INTO USER_SESSIONS VALUES (16, 2, 'oschmidt@globaltech.io', TIMESTAMP '2024-08-03 08:30:00', TIMESTAMP '2024-08-03 16:00:00', '10.10.0.60');
INSERT INTO USER_SESSIONS VALUES (17, 2, 'epatel@globaltech.io', TIMESTAMP '2024-08-04 10:00:00', NULL, '10.10.1.35');
INSERT INTO USER_SESSIONS VALUES (18, 2, 'irossi@globaltech.io', TIMESTAMP '2024-08-04 09:15:00', TIMESTAMP '2024-08-04 17:45:00', '10.10.0.70');

-- Tenant 3: StartupXYZ - 5 sessions
INSERT INTO USER_SESSIONS VALUES (19, 3, 'rcooper@startupxyz.co', TIMESTAMP '2024-08-01 10:00:00', TIMESTAMP '2024-08-01 22:00:00', '203.0.113.10');
INSERT INTO USER_SESSIONS VALUES (20, 3, 'amorgan@startupxyz.co', TIMESTAMP '2024-08-02 09:30:00', TIMESTAMP '2024-08-02 18:30:00', '203.0.113.11');
INSERT INTO USER_SESSIONS VALUES (21, 3, 'khuang@startupxyz.co', TIMESTAMP '2024-08-03 08:00:00', TIMESTAMP '2024-08-03 20:00:00', '198.51.100.5');
INSERT INTO USER_SESSIONS VALUES (22, 3, 'nfoster@startupxyz.co', TIMESTAMP '2024-08-04 11:00:00', TIMESTAMP '2024-08-04 17:00:00', '203.0.113.15');
INSERT INTO USER_SESSIONS VALUES (23, 3, 'brivera@startupxyz.co', TIMESTAMP '2024-08-05 09:00:00', NULL, '198.51.100.8');
COMMIT;
EXIT;
EOSQL

echo "All data inserted."

# -------------------------------------------------------
# Step 8: Create the APPLICATION CONTEXT (must be done as SYSTEM/SYS)
# -------------------------------------------------------
echo "Creating application context TENANT_CTX..."
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
CREATE OR REPLACE CONTEXT TENANT_CTX USING saas_admin.TENANT_CTX_PKG;
EXIT;
EOSQL

echo "Application context created."

# -------------------------------------------------------
# Step 9: Create the context package WITH INTENTIONAL BUG
# Bug: defaults to tenant_id=0 (superuser) instead of -1 (no access) when NULL
# -------------------------------------------------------
echo "Creating TENANT_CTX_PKG (with intentional bug)..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
CREATE OR REPLACE PACKAGE TENANT_CTX_PKG AS
    PROCEDURE SET_TENANT_ID(p_tenant_id IN NUMBER);
END;
/

CREATE OR REPLACE PACKAGE BODY TENANT_CTX_PKG AS
    PROCEDURE SET_TENANT_ID(p_tenant_id IN NUMBER) IS
    BEGIN
        -- BUG: When p_tenant_id is NULL, defaults to 0 (superuser) instead of -1 (no access)
        IF p_tenant_id IS NULL THEN
            DBMS_SESSION.SET_CONTEXT('TENANT_CTX', 'TENANT_ID', '0');
        ELSE
            DBMS_SESSION.SET_CONTEXT('TENANT_CTX', 'TENANT_ID', TO_CHAR(p_tenant_id));
        END IF;
    END;
END;
/
EXIT;
EOSQL

echo "Context package created with intentional bug."

# -------------------------------------------------------
# Step 10: Create the VPD policy function WITH INTENTIONAL BUG
# Bug: Returns NULL (no filtering) instead of '1=0' (deny all) when context not set
# -------------------------------------------------------
echo "Creating TENANT_ISOLATION_POLICY function (with intentional bug)..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
CREATE OR REPLACE FUNCTION TENANT_ISOLATION_POLICY(
    p_schema IN VARCHAR2,
    p_table IN VARCHAR2
) RETURN VARCHAR2 AS
    v_tenant_id VARCHAR2(20);
BEGIN
    v_tenant_id := SYS_CONTEXT('TENANT_CTX', 'TENANT_ID');
    -- BUG: Returns NULL (empty predicate = no filtering) when context not set
    -- instead of returning '1=0' (deny all access)
    IF v_tenant_id IS NULL OR v_tenant_id = '0' THEN
        RETURN NULL;  -- THIS IS THE BUG: NULL means no restriction!
    END IF;
    RETURN 'tenant_id = ' || v_tenant_id;
END;
/
EXIT;
EOSQL

echo "VPD policy function created with intentional bug."

# -------------------------------------------------------
# Step 11: Add VPD policy ONLY on CUSTOMER_DATA
# Intentionally skip FINANCIAL_RECORDS - this is error #2
# -------------------------------------------------------
echo "Adding VPD policy on CUSTOMER_DATA only (intentionally skipping FINANCIAL_RECORDS)..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
BEGIN
    DBMS_RLS.ADD_POLICY(
        object_schema   => 'SAAS_ADMIN',
        object_name     => 'CUSTOMER_DATA',
        policy_name     => 'CUSTOMER_TENANT_POLICY',
        function_schema => 'SAAS_ADMIN',
        policy_function => 'TENANT_ISOLATION_POLICY',
        statement_types => 'SELECT,INSERT,UPDATE,DELETE'
    );
END;
/
EXIT;
EOSQL

echo "VPD policy added on CUSTOMER_DATA (FINANCIAL_RECORDS intentionally unprotected)."

# -------------------------------------------------------
# Step 12: Grant SELECT privileges on data tables to tenant users
# -------------------------------------------------------
echo "Granting SELECT privileges to tenant users..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
GRANT SELECT ON TENANTS TO tenant1_user;
GRANT SELECT ON TENANTS TO tenant2_user;
GRANT SELECT ON TENANTS TO tenant3_user;

GRANT SELECT ON CUSTOMER_DATA TO tenant1_user;
GRANT SELECT ON CUSTOMER_DATA TO tenant2_user;
GRANT SELECT ON CUSTOMER_DATA TO tenant3_user;

GRANT SELECT ON FINANCIAL_RECORDS TO tenant1_user;
GRANT SELECT ON FINANCIAL_RECORDS TO tenant2_user;
GRANT SELECT ON FINANCIAL_RECORDS TO tenant3_user;

GRANT SELECT ON API_KEYS TO tenant1_user;
GRANT SELECT ON API_KEYS TO tenant2_user;
GRANT SELECT ON API_KEYS TO tenant3_user;

GRANT SELECT ON USER_SESSIONS TO tenant1_user;
GRANT SELECT ON USER_SESSIONS TO tenant2_user;
GRANT SELECT ON USER_SESSIONS TO tenant3_user;

EXIT;
EOSQL

echo "SELECT privileges granted."

# -------------------------------------------------------
# Grant EXECUTE on context package to tenant users
# -------------------------------------------------------
echo "Granting EXECUTE on context package to tenant users..."
sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
GRANT EXECUTE ON TENANT_CTX_PKG TO tenant1_user;
GRANT EXECUTE ON TENANT_CTX_PKG TO tenant2_user;
GRANT EXECUTE ON TENANT_CTX_PKG TO tenant3_user;
EXIT;
EOSQL

echo "EXECUTE privileges granted on context package."

# -------------------------------------------------------
# Record baseline state for verification
# -------------------------------------------------------
echo "Recording baseline state..."

# Count records per table
CUSTOMER_COUNT=$(sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM CUSTOMER_DATA;
EXIT;
EOSQL
)
CUSTOMER_COUNT=$(echo "$CUSTOMER_COUNT" | tr -d '[:space:]')

FINANCIAL_COUNT=$(sudo docker exec -i oracle-xe sqlplus -s saas_admin/SaaS2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM FINANCIAL_RECORDS;
EXIT;
EOSQL
)
FINANCIAL_COUNT=$(echo "$FINANCIAL_COUNT" | tr -d '[:space:]')

echo "Baseline: ${CUSTOMER_COUNT} customer records, ${FINANCIAL_COUNT} financial records"

# -------------------------------------------------------
# Step 14: Ensure SQL Developer is running
# -------------------------------------------------------
echo "Ensuring SQL Developer is running..."

# Pre-configure SaaS Admin connection
ensure_hr_connection "SaaS Admin DB" "saas_admin" "SaaS2024"
sleep 2

SQLDEVELOPER_PID=$(pgrep -f "sqldeveloper" | head -1)
if [ -z "$SQLDEVELOPER_PID" ]; then
    echo "Starting SQL Developer..."
    sudo -u ga DISPLAY=:1 /opt/sqldeveloper/sqldeveloper.sh &
    sleep 15
fi

# Focus and maximize SQL Developer
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# -------------------------------------------------------
# Step 15: Take initial screenshot
# -------------------------------------------------------
echo "Taking initial screenshot..."
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo ""
echo "=== Multi-Tenant VPD Data Isolation Setup Complete ==="
echo ""
echo "Schema: SAAS_PLATFORM (user: saas_admin/SaaS2024)"
echo "Tenants:"
echo "  1. Acme Corp (ENTERPRISE) - 15 customers, 20 financials, 3 API keys, 10 sessions"
echo "  2. GlobalTech Inc (PROFESSIONAL) - 12 customers, 18 financials, 2 API keys, 8 sessions"
echo "  3. StartupXYZ (STARTER) - 8 customers, 10 financials, 1 API key, 5 sessions"
echo ""
echo "Intentional security flaws injected:"
echo "  1. TENANT_ISOLATION_POLICY returns NULL (no filter) when context not set or tenant_id=0"
echo "  2. FINANCIAL_RECORDS table has NO VPD policy (completely unprotected)"
echo "  3. TENANT_CTX_PKG defaults to tenant_id=0 (superuser) instead of -1 (no access)"
