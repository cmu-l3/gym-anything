#!/bin/bash
echo "=== Setting up SAM License Audit Reconciliation ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# 1. Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# 2. Clean up previous run artifacts
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER sam_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# 3. Create schema
echo "Creating SAM_ADMIN schema..."
oracle_query "CREATE USER sam_admin IDENTIFIED BY SamAdmin2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO sam_admin;
GRANT RESOURCE TO sam_admin;
GRANT CREATE VIEW TO sam_admin;
GRANT CREATE MATERIALIZED VIEW TO sam_admin;
GRANT CREATE PROCEDURE TO sam_admin;
GRANT CREATE SESSION TO sam_admin;
GRANT CREATE TABLE TO sam_admin;
EXIT;" "system"

# 4. Create Tables and Insert Data
echo "Creating tables and inserting data..."

sudo docker exec -i oracle-xe sqlplus -s sam_admin/SamAdmin2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE raw_cmdb_discovery (
    host_id VARCHAR2(50) PRIMARY KEY,
    cpu_cores NUMBER NOT NULL,
    environment_type VARCHAR2(10) NOT NULL,
    raw_software_string VARCHAR2(200) NOT NULL
);

CREATE TABLE software_catalog (
    product_name VARCHAR2(100) PRIMARY KEY,
    vendor VARCHAR2(100) NOT NULL,
    unit_price NUMBER NOT NULL
);

CREATE TABLE entitlements (
    entitlement_id NUMBER PRIMARY KEY,
    vendor VARCHAR2(100) NOT NULL,
    product_name VARCHAR2(100) NOT NULL,
    version VARCHAR2(50) NOT NULL,
    edition VARCHAR2(50) NOT NULL,
    quantity_owned NUMBER NOT NULL
);

-- Insert Software Catalog
INSERT INTO software_catalog VALUES ('Microsoft SQL Server', 'Microsoft', 3500);
INSERT INTO software_catalog VALUES ('Oracle Database', 'Oracle', 15000);
INSERT INTO software_catalog VALUES ('Windows Server', 'Microsoft', 1200);
INSERT INTO software_catalog VALUES ('Ubuntu Linux', 'Canonical', 0);

-- Insert Entitlements
INSERT INTO entitlements VALUES (1, 'Microsoft', 'Microsoft SQL Server', '2019', 'Enterprise', 2);
INSERT INTO entitlements VALUES (2, 'Microsoft', 'Microsoft SQL Server', '2017', 'Standard', 15);
INSERT INTO entitlements VALUES (3, 'Oracle', 'Oracle Database', '19c', 'Enterprise', 4);
INSERT INTO entitlements VALUES (4, 'Oracle', 'Oracle Database', '12c', 'Standard', 4);
INSERT INTO entitlements VALUES (5, 'Microsoft', 'Windows Server', '2022', 'Datacenter', 10);
INSERT INTO entitlements VALUES (6, 'Canonical', 'Ubuntu Linux', '20.04', 'LTS', 100);

-- Insert messy CMDB data
INSERT INTO raw_cmdb_discovery VALUES ('H-001', 2, 'PROD', 'MS SQL Svr 2019 Enterprise Ed.');
INSERT INTO raw_cmdb_discovery VALUES ('H-002', 32, 'DEV', 'Oracle Database 19c Enterprise');
INSERT INTO raw_cmdb_discovery VALUES ('H-003', 8, 'PROD', 'Windows Server 2022 Datacenter');
INSERT INTO raw_cmdb_discovery VALUES ('H-004', 11, 'PROD', 'Oracle DB 12c Standard Edition');
INSERT INTO raw_cmdb_discovery VALUES ('H-005', 10, 'PROD', 'SQL Server 2017 Standard');
INSERT INTO raw_cmdb_discovery VALUES ('H-006', 4, 'PROD', 'Ubuntu Linux 20.04 LTS');
INSERT INTO raw_cmdb_discovery VALUES ('H-007', 4, 'TEST', 'MS SQL Server 2019 Enterprise');
INSERT INTO raw_cmdb_discovery VALUES ('H-008', 16, 'PROD', 'Windows Server 2022 Datacenter');

COMMIT;
EXIT;
EOSQL

echo "Data populated."

# 5. Pre-configure SQL Developer connection
ensure_hr_connection "SAM Admin" "sam_admin" "SamAdmin2024"

# 6. Ensure export directory exists
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# 7. Start SQL Developer in the background (agent will interact with it)
if ! pgrep -f sqldeveloper > /dev/null; then
    echo "Starting SQL Developer..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper &"
    sleep 15
fi

# Maximize SQL Developer and open connection
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Setup complete ==="