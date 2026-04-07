#!/bin/bash
echo "=== Setting up Campaign Finance Donor Deduplication ==="

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

echo "Setting up ELECTIONS_ADMIN schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER elections_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER elections_admin IDENTIFIED BY Elections2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO elections_admin;
GRANT RESOURCE TO elections_admin;
GRANT CREATE VIEW TO elections_admin;
GRANT CREATE MATERIALIZED VIEW TO elections_admin;
GRANT CREATE TABLE TO elections_admin;
GRANT CREATE SESSION TO elections_admin;
EXIT;" "system"

echo "User created."

echo "Creating tables and inserting seed data..."
sudo docker exec -i oracle-xe sqlplus -s elections_admin/Elections2024@//localhost:1521/XEPDB1 << 'EOSQL'
CREATE TABLE raw_donors (
    donor_id NUMBER PRIMARY KEY,
    name VARCHAR2(200),
    city VARCHAR2(100),
    state VARCHAR2(2),
    zip_code VARCHAR2(10),
    employer VARCHAR2(100),
    occupation VARCHAR2(100)
);

CREATE TABLE contributions (
    transaction_id NUMBER PRIMARY KEY,
    donor_id NUMBER REFERENCES raw_donors(donor_id),
    committee_id VARCHAR2(20),
    transaction_dt DATE,
    transaction_amt NUMBER(10,2),
    report_type VARCHAR2(10)
);

-- Seed Data
INSERT INTO raw_donors VALUES (101, 'SCHWARZENEGGER, ARNOLD', 'LOS ANGELES', 'CA', '90210', 'ACTOR', 'SELF');
INSERT INTO raw_donors VALUES (102, 'SHWARZENEGGER, ARNOLD', 'LOS ANGELES', 'CA', '90210', 'ACTOR', 'SELF');
INSERT INTO raw_donors VALUES (103, 'SHWARZENEGER, ARNOLD', 'LOS ANGELES', 'CA', '90210', 'ACTOR', 'SELF');

INSERT INTO raw_donors VALUES (201, 'WASHINGTON, GEORGE', 'MT VERNON', 'VA', '22121', 'PRESIDENT', 'GOV');
INSERT INTO raw_donors VALUES (202, 'WASHINGON, GEORGE', 'MT VERNON', 'VA', '22121', 'PRESIDENT', 'GOV');
INSERT INTO raw_donors VALUES (203, 'WASHINGTON, GEORG', 'MT VERNON', 'VA', '22121', 'PRESIDENT', 'GOV');

INSERT INTO raw_donors VALUES (301, 'LINCOLN, ABRAHAM', 'SPRINGFIELD', 'IL', '62701', 'LAWYER', 'SELF');

INSERT INTO raw_donors VALUES (401, 'ZUCKERBERG, MARK', 'PALO ALTO', 'CA', '94301', 'CEO', 'META');
INSERT INTO raw_donors VALUES (402, 'ZUKERBERG, MARK', 'PALO ALTO', 'CA', '94301', 'CEO', 'META');

INSERT INTO raw_donors VALUES (501, 'DOE, JOHN', 'NEW YORK', 'NY', '10001', 'NONE', 'NONE');
INSERT INTO raw_donors VALUES (502, 'SMITH, JANE', 'NEW YORK', 'NY', '10001', 'NONE', 'NONE');

-- Arnold total: 3500 (Violator)
INSERT INTO contributions VALUES (1, 101, 'PAC1', SYSDATE, 2000, 'Q1');
INSERT INTO contributions VALUES (2, 102, 'PAC2', SYSDATE, 1000, 'Q2');
INSERT INTO contributions VALUES (3, 103, 'PAC1', SYSDATE, 500, 'Q3');

-- George total: 3000 (Safe)
INSERT INTO contributions VALUES (4, 201, 'PAC1', SYSDATE, 1000, 'Q1');
INSERT INTO contributions VALUES (5, 202, 'PAC2', SYSDATE, 1000, 'Q2');
INSERT INTO contributions VALUES (6, 203, 'PAC3', SYSDATE, 1000, 'Q3');

-- Abe total: 3400 (Violator)
INSERT INTO contributions VALUES (7, 301, 'PAC1', SYSDATE, 3400, 'Q1');

-- Mark total: 3300 (Safe)
INSERT INTO contributions VALUES (8, 401, 'PAC1', SYSDATE, 3000, 'Q1');
INSERT INTO contributions VALUES (9, 402, 'PAC1', SYSDATE, 300, 'Q2');

-- Safe donors
INSERT INTO contributions VALUES (10, 501, 'PAC1', SYSDATE, 100, 'Q1');
INSERT INTO contributions VALUES (11, 502, 'PAC1', SYSDATE, 100, 'Q1');

COMMIT;
EXIT;
EOSQL

echo "Data populated successfully."

# Setup export directory
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Pre-configure SQL Developer connection
ensure_hr_connection "Elections Database" "elections_admin" "Elections2024"

# Focus SQL developer if it's already open
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="