#!/bin/bash
# Setup script for Short-Term Rental Ordinance Enforcement task
echo "=== Setting up Short-Term Rental Ordinance Enforcement ==="

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
  EXECUTE IMMEDIATE 'DROP USER housing_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

rm -f /home/ga/Documents/exports/illegal_str_targets.csv 2>/dev/null || true
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

sleep 2

# ---------------------------------------------------------------
# 3. Create HOUSING_ADMIN schema
# ---------------------------------------------------------------
echo "Creating HOUSING_ADMIN schema..."

oracle_query "CREATE USER housing_admin IDENTIFIED BY Housing2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO housing_admin;
GRANT RESOURCE TO housing_admin;
GRANT CREATE VIEW TO housing_admin;
GRANT CREATE MATERIALIZED VIEW TO housing_admin;
GRANT CREATE PROCEDURE TO housing_admin;
GRANT CREATE SESSION TO housing_admin;
GRANT CREATE TABLE TO housing_admin;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create housing_admin user"
    exit 1
fi
echo "housing_admin user created with required privileges"

# ---------------------------------------------------------------
# 4. Create Tables and Insert Data
# ---------------------------------------------------------------
echo "Creating HOUSING_ADMIN tables and populating data..."

sudo docker exec -i oracle-xe sqlplus -s housing_admin/Housing2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE city_licenses (
    license_number   VARCHAR2(20) PRIMARY KEY,
    status           VARCHAR2(20),
    issue_date       DATE,
    expiration_date  DATE,
    property_address VARCHAR2(255),
    owner_name       VARCHAR2(100)
);

CREATE TABLE str_listings (
    listing_id        NUMBER PRIMARY KEY,
    name              VARCHAR2(255),
    host_id           NUMBER,
    host_name         VARCHAR2(100),
    neighbourhood     VARCHAR2(100),
    room_type         VARCHAR2(50),
    price             NUMBER(8,2),
    minimum_nights    NUMBER,
    number_of_reviews NUMBER,
    reviews_per_month NUMBER(5,2),
    license           VARCHAR2(100),
    description       CLOB
);

-- Insert Official Licenses
INSERT INTO city_licenses VALUES ('STR-2023-0001', 'ACTIVE',  DATE '2023-01-15', DATE '2024-01-14', '101 Main St', 'Alice Smith');
INSERT INTO city_licenses VALUES ('STR-2023-0002', 'EXPIRED', DATE '2022-05-10', DATE '2023-05-09', '202 Oak St',  'Bob Jones');
INSERT INTO city_licenses VALUES ('STR-2023-0003', 'ACTIVE',  DATE '2023-08-01', DATE '2024-07-31', '303 Pine St', 'Charlie Brown');
INSERT INTO city_licenses VALUES ('STR-2023-0004', 'REVOKED', DATE '2023-02-20', DATE '2024-02-19', '404 Elm St',  'Diana Prince');
INSERT INTO city_licenses VALUES ('STR-2023-0005', 'ACTIVE',  DATE '2023-11-05', DATE '2024-11-04', '505 Maple St','Evan Wright');
INSERT INTO city_licenses VALUES ('STR-2023-0006', 'ACTIVE',  DATE '2023-06-15', DATE '2024-06-14', '606 Cedar St','Fiona Gallagher');

-- Insert Listings (Injecting specific violations)

-- 1. Valid Listing (No violations)
INSERT INTO str_listings VALUES (1001, 'Cozy Downtown Apt', 501, 'Alice', 'Downtown', 'Entire home/apt', 150, 2, 45, 1.5, 'STR-2023-0001', 'Great views and close to transit.');

-- 2. Hidden valid license in description (Should be extracted and valid, no violations)
INSERT INTO str_listings VALUES (1002, 'Sunny Room', 502, 'Charlie', 'Westside', 'Private room', 80, 1, 12, 0.5, 'Pending', 'License: STR-2023-0003. Welcome to my home!');

-- 3. UNLICENSED (No license anywhere)
INSERT INTO str_listings VALUES (1003, 'Luxury Loft', 503, 'Eve', 'Downtown', 'Entire home/apt', 300, 3, 5, 0.2, 'Exempt', 'This property does not need a license.');

-- 4. EXPIRED (In license column)
INSERT INTO str_listings VALUES (1004, 'Oak Street House', 504, 'Bob', 'Northside', 'Entire home/apt', 200, 2, 80, 2.1, 'STR-2023-0002', 'Spacious house for families.');

-- 5. REVOKED (Hidden in description)
INSERT INTO str_listings VALUES (1005, 'Elm Street Studio', 505, 'Diana', 'Southside', 'Entire home/apt', 120, 1, 150, 4.0, NULL, 'City Reg: STR-2023-0004.');

-- 6 & 7. DUPLICATE LICENSE (Two different listings claiming STR-2023-0005)
INSERT INTO str_listings VALUES (1006, 'Maple Suite A', 506, 'Evan', 'Eastside', 'Entire home/apt', 140, 2, 30, 1.0, 'STR-2023-0005', 'Suite A.');
INSERT INTO str_listings VALUES (1007, 'Maple Suite B', 507, 'Frank', 'Eastside', 'Entire home/apt', 145, 2, 25, 0.8, 'STR-2023-0005', 'Suite B.');

-- 8, 9, 10. COMMERCIAL OPERATOR (Host 999 has 3 'Entire home/apt' listings)
INSERT INTO str_listings VALUES (1008, 'Corp Housing 1', 999, 'MegaCorp', 'Downtown', 'Entire home/apt', 250, 30, 5, 0.5, 'STR-2023-0006', 'Corporate housing.');
INSERT INTO str_listings VALUES (1009, 'Corp Housing 2', 999, 'MegaCorp', 'Downtown', 'Entire home/apt', 250, 30, 2, 0.2, 'STR-2023-0006', 'Corporate housing.');
INSERT INTO str_listings VALUES (1010, 'Corp Housing 3', 999, 'MegaCorp', 'Downtown', 'Entire home/apt', 250, 30, 1, 0.1, 'STR-2023-0006', 'Corporate housing.');

-- 11. OVER_LIMIT (High occupancy estimate: 4.5 reviews/mo * 12 * 2 * 2 nights = 216 nights > 90)
INSERT INTO str_listings VALUES (1011, 'Party House', 508, 'Gary', 'Westside', 'Entire home/apt', 400, 2, 200, 4.5, 'STR-2023-0001', 'Always booked! Great for weekends.');

COMMIT;
EXIT;
EOSQL

echo "Data populated successfully."

# -------------------------------------------------------
# 5. Pre-configure SQL Developer Connection
# -------------------------------------------------------
echo "Configuring SQL Developer connection for housing_admin..."
ensure_hr_connection "Housing DB" "housing_admin" "Housing2024"

# -------------------------------------------------------
# 6. Launch SQL Developer
# -------------------------------------------------------
if ! pgrep -f "sqldeveloper" > /dev/null; then
    echo "Starting SQL Developer..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper &"
    sleep 15
fi

# Try to open the connection directly
open_hr_connection_in_sqldeveloper "Housing DB"

# Maximize SQL Developer
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="