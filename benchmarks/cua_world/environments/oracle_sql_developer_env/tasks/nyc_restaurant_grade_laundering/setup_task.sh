#!/bin/bash
# Setup script for NYC Restaurant Grade Laundering Detection task
echo "=== Setting up NYC Restaurant Grade Laundering Task ==="

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

# 2. Clean up and setup User
echo "Setting up HEALTH_AUDITOR schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER health_auditor CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER health_auditor IDENTIFIED BY Audit2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO health_auditor;
GRANT RESOURCE TO health_auditor;
GRANT CREATE VIEW TO health_auditor;
GRANT CREATE MATERIALIZED VIEW TO health_auditor;
GRANT CREATE SESSION TO health_auditor;
GRANT EXECUTE ON UTL_MATCH TO health_auditor;
EXIT;" "system"

echo "HEALTH_AUDITOR user created with required privileges"

# 3. Create Tables
echo "Creating tables..."
sudo docker exec -i oracle-xe sqlplus -s health_auditor/Audit2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE restaurants (
  camis           NUMBER PRIMARY KEY,
  dba             VARCHAR2(200) NOT NULL,
  boro            VARCHAR2(50),
  building        VARCHAR2(20),
  street          VARCHAR2(100),
  zipcode         VARCHAR2(10),
  phone           VARCHAR2(20),
  cuisine_type    VARCHAR2(50),
  date_established DATE
);

CREATE TABLE inspections (
  inspection_id   NUMBER PRIMARY KEY,
  camis           NUMBER REFERENCES restaurants(camis),
  inspection_date DATE,
  action          VARCHAR2(200),
  score           NUMBER,
  grade           VARCHAR2(1),
  inspection_type VARCHAR2(100)
);

CREATE TABLE violations (
  violation_id    NUMBER PRIMARY KEY,
  inspection_id   NUMBER REFERENCES inspections(inspection_id),
  violation_code  VARCHAR2(10),
  critical_flag   VARCHAR2(1),
  violation_desc  VARCHAR2(500)
);

-- ==========================================
-- INSERT SEED DATA
-- ==========================================

-- CHAIN 1: Fuzzy Name Laundering (1001 -> 1002 -> 1003)
-- 1001 gets a bad score (35). 1002 opens 2 months later, same building/street, similar name.
-- 1002 gets a bad score (30). 1003 opens 4 months later.
INSERT INTO restaurants VALUES (1001, 'DIRTY BIRD FRIED CHICKEN', 'Manhattan', '123', 'MAIN ST', '10001', '5550001', 'Chicken', DATE '2020-01-01');
INSERT INTO restaurants VALUES (1002, 'DIRTY BIRDS FRIED CHICKEN', 'Manhattan', '123', 'MAIN ST', '10001', '5550002', 'Chicken', DATE '2023-02-15');
INSERT INTO restaurants VALUES (1003, 'DIRTY BIRD CHICKEN', 'Manhattan', '123', 'MAIN ST', '10001', '5550003', 'Chicken', DATE '2023-10-01');

INSERT INTO inspections VALUES (1, 1001, DATE '2023-01-10', 'Violations cited', 35, 'C', 'Initial');
INSERT INTO inspections VALUES (2, 1002, DATE '2023-03-01', 'Violations cited', 30, 'C', 'Initial');
INSERT INTO inspections VALUES (3, 1003, DATE '2023-07-01', 'Violations cited', 12, 'A', 'Initial');

-- Chain 1 Violations (Total critical = 5 + 4 + 0 = 9)
INSERT INTO violations VALUES (101, 1, '04L', 'Y', 'Evidence of mice');
INSERT INTO violations VALUES (102, 1, '06A', 'Y', 'Personal hygiene');
INSERT INTO violations VALUES (103, 1, '02G', 'Y', 'Cold food held above 41F');
INSERT INTO violations VALUES (104, 1, '04N', 'Y', 'Filth flies');
INSERT INTO violations VALUES (105, 1, '04M', 'Y', 'Live roaches');

INSERT INTO violations VALUES (106, 2, '04L', 'Y', 'Evidence of mice');
INSERT INTO violations VALUES (107, 2, '06A', 'Y', 'Personal hygiene');
INSERT INTO violations VALUES (108, 2, '04N', 'Y', 'Filth flies');
INSERT INTO violations VALUES (109, 2, '04M', 'Y', 'Live roaches');

INSERT INTO violations VALUES (110, 3, '10F', 'N', 'Non-food contact surface dirty');


-- CHAIN 2: Exact Phone Laundering (2001 -> 2002 -> 2003)
-- Radically different names, but exact same phone and location
INSERT INTO restaurants VALUES (2001, 'TASTY NOODLES', 'Queens', '456', 'BROADWAY', '11101', '5551234', 'Asian', DATE '2019-05-01');
INSERT INTO restaurants VALUES (2002, 'NEW NOODLE HOUSE', 'Queens', '456', 'BROADWAY', '11101', '5551234', 'Asian', DATE '2022-12-01');
INSERT INTO restaurants VALUES (2003, 'GOLDEN NOODLES', 'Queens', '456', 'BROADWAY', '11101', '5551234', 'Asian', DATE '2023-06-15');

INSERT INTO inspections VALUES (4, 2001, DATE '2022-11-05', 'Violations cited', 29, 'C', 'Initial');
INSERT INTO inspections VALUES (5, 2002, DATE '2023-01-20', 'Violations cited', 32, 'C', 'Initial');
INSERT INTO inspections VALUES (6, 2003, DATE '2023-05-15', 'Violations cited', 15, 'B', 'Initial');

-- Chain 2 Violations (Total critical = 6 + 5 + 1 = 12)
INSERT INTO violations VALUES (201, 4, '02B', 'Y', 'Hot food not held at 140F');
INSERT INTO violations VALUES (202, 4, '04L', 'Y', 'Mice');
INSERT INTO violations VALUES (203, 4, '06C', 'Y', 'Food source');
INSERT INTO violations VALUES (204, 4, '02G', 'Y', 'Cold food');
INSERT INTO violations VALUES (205, 4, '04N', 'Y', 'Flies');
INSERT INTO violations VALUES (206, 4, '06A', 'Y', 'Hygiene');

INSERT INTO violations VALUES (207, 5, '02B', 'Y', 'Hot food not held at 140F');
INSERT INTO violations VALUES (208, 5, '04L', 'Y', 'Mice');
INSERT INTO violations VALUES (209, 5, '04N', 'Y', 'Flies');
INSERT INTO violations VALUES (210, 5, '06A', 'Y', 'Hygiene');
INSERT INTO violations VALUES (211, 5, '04M', 'Y', 'Roaches');

INSERT INTO violations VALUES (212, 6, '04L', 'Y', 'Mice');


-- NOISE DATA 1: Good score before transition (not grade laundering)
INSERT INTO restaurants VALUES (3001, 'CLEAN KITCHEN', 'Brooklyn', '789', 'SMITH ST', '11201', '5559999', 'American', DATE '2015-01-01');
INSERT INTO restaurants VALUES (3002, 'CLEANER KITCHEN', 'Brooklyn', '789', 'SMITH ST', '11201', '5559999', 'American', DATE '2023-01-01');
INSERT INTO inspections VALUES (7, 3001, DATE '2022-12-01', 'Pass', 10, 'A', 'Initial');
INSERT INTO inspections VALUES (8, 3002, DATE '2023-02-01', 'Pass', 8, 'A', 'Initial');
INSERT INTO violations VALUES (301, 7, '10F', 'N', 'Surface dirty');

-- NOISE DATA 2: Over 180 days gap
INSERT INTO restaurants VALUES (4001, 'SLOW CHICKEN', 'Bronx', '321', 'GRAND CONCOURSE', '10451', '5558888', 'Chicken', DATE '2018-01-01');
INSERT INTO restaurants VALUES (4002, 'SLOW CHICKENS', 'Bronx', '321', 'GRAND CONCOURSE', '10451', '5558888', 'Chicken', DATE '2023-01-01');
INSERT INTO inspections VALUES (9, 4001, DATE '2021-01-01', 'Violations', 40, 'C', 'Initial');
INSERT INTO inspections VALUES (10, 4002, DATE '2023-05-01', 'Pass', 12, 'A', 'Initial'); -- gap > 180 days

COMMIT;
EXIT;
EOSQL

echo "Data populated successfully"

# 4. Create Export Directory
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

# 5. Configure SQL Developer Connection
mkdir -p /home/ga/.sqldeveloper/system24.3.0.284.2209/o.jdeveloper.db.connection.24.2.0.284.2209
cat > /home/ga/.sqldeveloper/system24.3.0.284.2209/o.jdeveloper.db.connection.24.2.0.284.2209/connections.json << 'CONNEOF'
{
  "connections": [
    {
      "name": "Health Auditor DB",
      "type": "jdbc",
      "info": {
        "SavePassword": "true",
        "OracleConnectionType": "BASIC",
        "customUrl": "jdbc:oracle:thin:@localhost:1521/XEPDB1",
        "hostname": "localhost",
        "driver": "oracle.jdbc.OracleDriver",
        "port": "1521",
        "ConnName": "Health Auditor DB",
        "serviceName": "XEPDB1",
        "user": "health_auditor",
        "password": "Audit2024"
      }
    }
  ]
}
CONNEOF
chown -R ga:ga /home/ga/.sqldeveloper

# 6. Launch SQL Developer
echo "Launching SQL Developer..."
su - ga -c "DISPLAY=:1 JAVA_TOOL_OPTIONS='--add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED -Dsun.java2d.xrender=false -Dsun.java2d.opengl=false' /opt/sqldeveloper/sqldeveloper.sh > /tmp/sqldeveloper.log 2>&1 &"

# Wait for UI and maximize
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 2
done

sleep 2
# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="