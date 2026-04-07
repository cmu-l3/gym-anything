#!/bin/bash
# Setup script for Public Health Database Optimization task
echo "=== Setting up Public Health Database Optimization Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER health_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# Create schema and grant privileges
echo "Creating HEALTH_ADMIN schema..."
oracle_query "CREATE USER health_admin IDENTIFIED BY Health2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE MATERIALIZED VIEW, CREATE TABLE TO health_admin;
GRANT GLOBAL QUERY REWRITE TO health_admin;
EXIT;" "system"

# Create the primary table
echo "Creating FOOD_INSPECTIONS table and inserting data..."
sudo docker exec -i oracle-xe sqlplus -s health_admin/Health2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE food_inspections (
    inspection_id NUMBER PRIMARY KEY,
    dba_name VARCHAR2(200),
    license_no NUMBER,
    facility_type VARCHAR2(100),
    risk VARCHAR2(50),
    address VARCHAR2(200),
    city VARCHAR2(50),
    state VARCHAR2(2),
    zip_code VARCHAR2(10),
    inspection_date DATE,
    inspection_type VARCHAR2(100),
    results VARCHAR2(50),
    violations CLOB
);

-- Insert realistic sample records (simulated Chicago Open Data)
INSERT INTO food_inspections VALUES (101, 'THE BURGER JOINT', 11111, 'Restaurant', 'Risk 1 (High)', '123 MAIN ST', 'CHICAGO', 'IL', '60601', DATE '2023-01-15', 'Canvass', 'Pass', 'No violations observed.');
INSERT INTO food_inspections VALUES (102, 'SALLY''S SALADS', 22222, 'Restaurant', 'Risk 2 (Medium)', '456 OAK ST', 'CHICAGO', 'IL', '60602', DATE '2023-02-10', 'Complaint', 'Pass w/ Conditions', '3. MANAGEMENT, FOOD EMPLOYEE AND CONDITIONAL EMPLOYEE; KNOWLEDGE, RESPONSIBILITIES AND REPORTING - Comments: Observed missing health policy.');
INSERT INTO food_inspections VALUES (103, 'PIZZA PALACE', 33333, 'Restaurant', 'Risk 1 (High)', '789 PINE ST', 'CHICAGO', 'IL', '60603', DATE '2023-03-22', 'Canvass', 'Fail', '38. INSECTS, RODENTS, & ANIMALS NOT PRESENT - Comments: Observed approximately 15 mouse droppings scattered under the dishwashing sink.');
INSERT INTO food_inspections VALUES (104, 'TACO TOWN', 44444, 'Restaurant', 'Risk 1 (High)', '321 ELM ST', 'CHICAGO', 'IL', '60604', DATE '2023-04-05', 'Canvass', 'Fail', '10. ADEQUATE HANDWASHING SINKS PROPERLY SUPPLIED AND ACCESSIBLE - Comments: Missing soap at handwash sink. Also observed a dead roach near back door.');

-- Chronic offender test case (License 99999 has 3 fails within 365 days)
INSERT INTO food_inspections VALUES (201, 'CHRONIC CAFE', 99999, 'Restaurant', 'Risk 1 (High)', '555 BAD ST', 'CHICAGO', 'IL', '60605', DATE '2022-01-10', 'Canvass', 'Fail', 'Food stored at improper temps.');
INSERT INTO food_inspections VALUES (202, 'CHRONIC CAFE', 99999, 'Restaurant', 'Risk 1 (High)', '555 BAD ST', 'CHICAGO', 'IL', '60605', DATE '2022-06-15', 'Canvass Re-Inspection', 'Fail', 'Still improper temps.');
INSERT INTO food_inspections VALUES (203, 'CHRONIC CAFE', 99999, 'Restaurant', 'Risk 1 (High)', '555 BAD ST', 'CHICAGO', 'IL', '60605', DATE '2022-12-01', 'Complaint', 'Fail', 'No hot water.');
INSERT INTO food_inspections VALUES (204, 'CHRONIC CAFE', 99999, 'Restaurant', 'Risk 1 (High)', '555 BAD ST', 'CHICAGO', 'IL', '60605', DATE '2024-01-15', 'Canvass', 'Fail', 'This fail is > 365 days after the last one, so rolling count drops.');

COMMIT;
EXIT;
EOSQL

echo "Data loaded."

# Pre-configure SQL Developer Connection
ensure_hr_connection "Health Database" "health_admin" "Health2024"

# Set up target directories
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Start Oracle SQL Developer
echo "Launching SQL Developer..."
if ! pgrep -f "sqldeveloper" > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper > /tmp/sqldeveloper_launch.log 2>&1 &"
fi

# Wait and maximize
sleep 15
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Open the connection so agent sees it
open_hr_connection_in_sqldeveloper

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task Setup Complete ==="