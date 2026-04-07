#!/bin/bash
# Setup script for Semiconductor Wafer Yield Analysis
echo "=== Setting up Semiconductor Wafer Yield Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# ---------------------------------------------------------------
# Verify Oracle Container is Running
# ---------------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# ---------------------------------------------------------------
# Clean up previous run artifacts
# ---------------------------------------------------------------
echo "Cleaning up previous run artifacts..."

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER fab_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# Create Schema and User
# ---------------------------------------------------------------
echo "Creating FAB_ANALYTICS schema (fab_admin user)..."

oracle_query "CREATE USER fab_admin IDENTIFIED BY Yield2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO fab_admin;
GRANT RESOURCE TO fab_admin;
GRANT CREATE VIEW TO fab_admin;
GRANT CREATE PROCEDURE TO fab_admin;
GRANT CREATE SESSION TO fab_admin;
EXIT;" "system"

# ---------------------------------------------------------------
# Create Tables and Generate Realistic Defect Topologies
# ---------------------------------------------------------------
echo "Creating tables and inserting patterned defect data..."

sudo docker exec -i oracle-xe sqlplus -s fab_admin/Yield2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE products (
    product_id   NUMBER PRIMARY KEY,
    product_name VARCHAR2(100) NOT NULL,
    node_nm      NUMBER,
    expected_yield_pct NUMBER(5,2)
);

CREATE TABLE lots (
    lot_id       NUMBER PRIMARY KEY,
    product_id   NUMBER REFERENCES products(product_id),
    lot_number   VARCHAR2(20) UNIQUE NOT NULL,
    start_date   DATE,
    completion_date DATE
);

CREATE TABLE wafers (
    wafer_id     NUMBER PRIMARY KEY,
    lot_id       NUMBER REFERENCES lots(lot_id),
    wafer_number NUMBER NOT NULL,
    radius_mm    NUMBER NOT NULL,
    center_x     NUMBER NOT NULL,
    center_y     NUMBER NOT NULL
);

CREATE TABLE defects (
    defect_id    NUMBER PRIMARY KEY,
    wafer_id     NUMBER REFERENCES wafers(wafer_id),
    x_coord      NUMBER(10,4) NOT NULL,
    y_coord      NUMBER(10,4) NOT NULL,
    defect_area_um2 NUMBER(10,4),
    class_code   VARCHAR2(10)
);

-- Generate Data using PL/SQL Block
DECLARE
  v_def_id NUMBER := 1;
  v_r      NUMBER;
  v_theta  NUMBER;
  v_x      NUMBER;
  v_y      NUMBER;
BEGIN
  -- Products and Lots
  INSERT INTO products VALUES (1, '14nm Logic Array', 14, 92.5);
  INSERT INTO lots VALUES (1, 1, 'L-99201A', SYSDATE-10, NULL);
  INSERT INTO lots VALUES (2, 1, 'L-99201B', SYSDATE-9, NULL);

  -- Wafer 1 (Lot 1): EDGE_RING Failure (Total = 70. 60 on edge > 90% of 150 radius)
  INSERT INTO wafers VALUES (1, 1, 1, 150, 0, 0);
  FOR i IN 1..60 LOOP
    v_theta := DBMS_RANDOM.VALUE(0, 6.28318);
    v_r := DBMS_RANDOM.VALUE(136, 148); -- Edge exclusion zone starts at 135 (90% of 150)
    INSERT INTO defects VALUES (v_def_id, 1, v_r * COS(v_theta), v_r * SIN(v_theta), DBMS_RANDOM.VALUE(0.1, 5), 'UNK');
    v_def_id := v_def_id + 1;
  END LOOP;
  FOR i IN 1..10 LOOP
    v_theta := DBMS_RANDOM.VALUE(0, 6.28318);
    v_r := DBMS_RANDOM.VALUE(0, 100);
    INSERT INTO defects VALUES (v_def_id, 1, v_r * COS(v_theta), v_r * SIN(v_theta), DBMS_RANDOM.VALUE(0.1, 5), 'UNK');
    v_def_id := v_def_id + 1;
  END LOOP;

  -- Wafer 2 (Lot 1): SCRATCH Failure (Total = 45. Highly correlated linear line + minor noise)
  INSERT INTO wafers VALUES (2, 1, 2, 150, 0, 0);
  FOR i IN 1..40 LOOP
    v_x := DBMS_RANDOM.VALUE(-100, 100);
    v_y := (1.2 * v_x) + DBMS_RANDOM.VALUE(-3, 3); -- R_Squared >= 0.8
    INSERT INTO defects VALUES (v_def_id, 2, v_x, v_y, DBMS_RANDOM.VALUE(0.1, 10), 'UNK');
    v_def_id := v_def_id + 1;
  END LOOP;
  FOR i IN 1..5 LOOP
    v_x := DBMS_RANDOM.VALUE(-50, 50);
    v_y := DBMS_RANDOM.VALUE(-50, 50);
    INSERT INTO defects VALUES (v_def_id, 2, v_x, v_y, DBMS_RANDOM.VALUE(0.1, 5), 'UNK');
    v_def_id := v_def_id + 1;
  END LOOP;

  -- Wafer 3 (Lot 1): RANDOM (Total = 20. Neither Edge nor Scratch, < 100 total)
  INSERT INTO wafers VALUES (3, 1, 3, 150, 0, 0);
  FOR i IN 1..20 LOOP
    v_x := DBMS_RANDOM.VALUE(-100, 100);
    v_y := DBMS_RANDOM.VALUE(-100, 100);
    INSERT INTO defects VALUES (v_def_id, 3, v_x, v_y, DBMS_RANDOM.VALUE(0.1, 5), 'UNK');
    v_def_id := v_def_id + 1;
  END LOOP;

  -- Wafer 4 (Lot 2): SCRAP by count limit (Total = 105. > 100, random distribution)
  INSERT INTO wafers VALUES (4, 2, 1, 150, 0, 0);
  FOR i IN 1..105 LOOP
    v_theta := DBMS_RANDOM.VALUE(0, 6.28318);
    v_r := DBMS_RANDOM.VALUE(0, 120);
    INSERT INTO defects VALUES (v_def_id, 4, v_r * COS(v_theta), v_r * SIN(v_theta), DBMS_RANDOM.VALUE(0.1, 5), 'UNK');
    v_def_id := v_def_id + 1;
  END LOOP;

  -- Wafer 5 (Lot 2): RANDOM (Total = 15. OK Wafer)
  INSERT INTO wafers VALUES (5, 2, 2, 150, 0, 0);
  FOR i IN 1..15 LOOP
    v_x := DBMS_RANDOM.VALUE(-50, 50);
    v_y := DBMS_RANDOM.VALUE(-50, 50);
    INSERT INTO defects VALUES (v_def_id, 5, v_x, v_y, DBMS_RANDOM.VALUE(0.1, 5), 'UNK');
    v_def_id := v_def_id + 1;
  END LOOP;

  COMMIT;
END;
/
EXIT;
EOSQL

echo "Database seeded with 5 wafers across 2 lots."

# ---------------------------------------------------------------
# Configure SQL Developer
# ---------------------------------------------------------------
# Make sure the export directory exists
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Setup connection in SQL Developer
ensure_hr_connection "FAB Database" "fab_admin" "Yield2024"

# Open the connection in SQL Developer if it's already running, else rely on user
open_hr_connection_in_sqldeveloper

# ---------------------------------------------------------------
# Finalize Setup
# ---------------------------------------------------------------
# Wait a moment for UI to settle
sleep 2
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task Setup Complete ==="