#!/bin/bash
# Setup script for Library Collections Audit task
echo "=== Setting up Library Collections Audit ==="

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

# --- Drop and recreate the LIBRARY_ADMIN user cleanly ---
echo "Setting up LIBRARY schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER library_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER library_admin IDENTIFIED BY Library2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO library_admin;
GRANT RESOURCE TO library_admin;
GRANT CREATE VIEW TO library_admin;
GRANT CREATE MATERIALIZED VIEW TO library_admin;
GRANT CREATE TABLE TO library_admin;
GRANT CREATE SESSION TO library_admin;
EXIT;" "system"

echo "LIBRARY_ADMIN user created with required privileges"

# --- Create tables and seed data in LIBRARY schema ---
sudo docker exec -i oracle-xe sqlplus -s library_admin/Library2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE catalog (
  bib_num NUMBER PRIMARY KEY,
  title VARCHAR2(255) NOT NULL,
  author VARCHAR2(255),
  publication_year NUMBER,
  isbn VARCHAR2(20),
  dewey_class VARCHAR2(20)
);

CREATE TABLE physical_items (
  item_barcode VARCHAR2(50) PRIMARY KEY,
  bib_num NUMBER REFERENCES catalog(bib_num),
  item_type VARCHAR2(50),
  item_collection VARCHAR2(50),
  item_status VARCHAR2(50),
  date_added DATE
);

CREATE TABLE circulation_history (
  transaction_id NUMBER PRIMARY KEY,
  item_barcode VARCHAR2(50) REFERENCES physical_items(item_barcode),
  checkout_date DATE,
  return_date DATE
);

CREATE TABLE active_holds (
  hold_id NUMBER PRIMARY KEY,
  bib_num NUMBER REFERENCES catalog(bib_num),
  patron_id NUMBER,
  hold_placed_date DATE,
  queue_position NUMBER
);

-- Insert Catalog Data
INSERT INTO catalog VALUES (1001, 'The Great Gatsby', 'F. Scott Fitzgerald', 1925, '9780743273565', '813.52');
INSERT INTO catalog VALUES (1002, 'A Brief History of Time', 'Stephen Hawking', 1988, '9780553380163', '523.1');
INSERT INTO catalog VALUES (1003, 'Old Obscure Book', 'Jane Doe', 1980, '1234567890', '301.2');
INSERT INTO catalog VALUES (1004, 'Lost Book', 'John Smith', 2000, '0987654321', '100');
INSERT INTO catalog VALUES (1005, 'Another Lost Book', 'Alice Jones', 2010, '1111111111', '823.9');
INSERT INTO catalog VALUES (1006, 'Fiction Book', 'Bob', 2015, '0000', 'FIC');

-- Insert Physical Items
INSERT INTO physical_items VALUES ('B001', 1001, 'BOOK', 'ADULT', 'AVAILABLE', DATE '2020-01-01');
INSERT INTO physical_items VALUES ('B002', 1002, 'BOOK', 'ADULT', 'AVAILABLE', DATE '2022-01-01');
INSERT INTO physical_items VALUES ('B003', 1003, 'BOOK', 'ADULT', 'AVAILABLE', DATE '2010-01-01');
INSERT INTO physical_items VALUES ('B004', 1004, 'BOOK', 'ADULT', 'LOST', DATE '2018-01-01');
INSERT INTO physical_items VALUES ('B005', 1003, 'BOOK', 'ADULT', 'AVAILABLE', DATE '2012-01-01');
INSERT INTO physical_items VALUES ('B006', 1006, 'BOOK', 'ADULT', 'AVAILABLE', DATE '2020-01-01');
INSERT INTO physical_items VALUES ('B007', 1005, 'BOOK', 'ADULT', 'LOST', DATE '2020-01-01');

-- Insert Circulation History
INSERT INTO circulation_history VALUES (1, 'B001', DATE '2023-05-01', DATE '2023-05-15');
INSERT INTO circulation_history VALUES (2, 'B001', DATE '2023-06-01', DATE '2023-06-15');
INSERT INTO circulation_history VALUES (3, 'B002', DATE '2023-07-01', DATE '2023-07-15');
INSERT INTO circulation_history VALUES (4, 'B003', DATE '2019-01-01', DATE '2019-01-15');

-- Insert Active Holds
INSERT INTO active_holds VALUES (1, 1001, 101, DATE '2024-01-01', 1);
INSERT INTO active_holds VALUES (2, 1001, 102, DATE '2024-01-02', 2);
INSERT INTO active_holds VALUES (3, 1001, 103, DATE '2024-01-03', 3);
INSERT INTO active_holds VALUES (4, 1001, 104, DATE '2024-01-04', 4);
INSERT INTO active_holds VALUES (5, 1001, 105, DATE '2024-01-05', 5);
INSERT INTO active_holds VALUES (6, 1004, 106, DATE '2024-02-01', 1);
INSERT INTO active_holds VALUES (7, 1005, 107, DATE '2024-03-01', 1);

COMMIT;
EXIT;
EOSQL

echo "Tables created and seeded."

# Make sure exports dir exists
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Setup SQL Developer connection JSON
ensure_hr_connection "Library Admin" "library_admin" "Library2024"

# Open the connection in SQL Developer
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="