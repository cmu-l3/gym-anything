#!/bin/bash
echo "=== Setting up Data Model Reverse Engineering Task ==="
source /workspace/scripts/task_utils.sh

# -------------------------------------------------------
# Drop and recreate LEGACY_OPS schema from scratch
# -------------------------------------------------------
oracle_query "BEGIN
  FOR u IN (SELECT username FROM dba_users WHERE username = 'LEGACY_OPS') LOOP
    EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
  END LOOP;
END;" "system" "OraclePassword123"

oracle_query "CREATE USER legacy_ops IDENTIFIED BY LegacyOps2024 DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS" "system" "OraclePassword123"
oracle_query "GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE, CREATE TRIGGER TO legacy_ops" "system" "OraclePassword123"
oracle_query "GRANT SELECT ON hr.employees TO legacy_ops" "system" "OraclePassword123"
oracle_query "GRANT SELECT ON hr.departments TO legacy_ops" "system" "OraclePassword123"
oracle_query "GRANT SELECT ON hr.jobs TO legacy_ops" "system" "OraclePassword123"
oracle_query "GRANT SELECT ON hr.countries TO legacy_ops" "system" "OraclePassword123"

echo "LEGACY_OPS user created."

# -------------------------------------------------------
# Create T_DEPT — department master (no PK, no comments)
# -------------------------------------------------------
oracle_query "CREATE TABLE legacy_ops.t_dept (
  dept_id   NUMBER(6),
  dept_nm   VARCHAR2(60),
  dept_loc  VARCHAR2(40)
)" "legacy_ops" "LegacyOps2024"

# Populate from real HR departments
oracle_query "INSERT INTO legacy_ops.t_dept
SELECT department_id, department_name,
  (SELECT city || ', ' || country_id FROM hr.locations WHERE location_id = d.location_id)
FROM hr.departments d
WHERE department_id IS NOT NULL" "legacy_ops" "LegacyOps2024"

oracle_query "COMMIT" "legacy_ops" "LegacyOps2024"
echo "T_DEPT created and populated."

# -------------------------------------------------------
# Create T_EMP — employee/sales staff (no PK, no comments)
# -------------------------------------------------------
oracle_query "CREATE TABLE legacy_ops.t_emp (
  emp_id    NUMBER(6),
  emp_nm    VARCHAR2(100),
  dept_id   NUMBER(6),
  hire_dt   DATE,
  salary    NUMBER(10,2)
)" "legacy_ops" "LegacyOps2024"

oracle_query "INSERT INTO legacy_ops.t_emp
SELECT employee_id, first_name || ' ' || last_name, department_id, hire_date, salary
FROM hr.employees" "legacy_ops" "LegacyOps2024"

oracle_query "COMMIT" "legacy_ops" "LegacyOps2024"
echo "T_EMP created and populated."

# -------------------------------------------------------
# Create T_CAT — product categories (no PK, no comments)
# -------------------------------------------------------
oracle_query "CREATE TABLE legacy_ops.t_cat (
  cat_id    NUMBER(4),
  cat_nm    VARCHAR2(50),
  cat_desc  VARCHAR2(200)
)" "legacy_ops" "LegacyOps2024"

oracle_query "INSERT INTO legacy_ops.t_cat VALUES (1, 'Electronics', 'Electronic devices and accessories')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_cat VALUES (2, 'Office Supplies', 'Stationery, paper, and office consumables')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_cat VALUES (3, 'Furniture', 'Office and facility furniture')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_cat VALUES (4, 'Software', 'Software licenses and subscriptions')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_cat VALUES (5, 'Services', 'Professional and consulting services')" "legacy_ops" "LegacyOps2024"
oracle_query "COMMIT" "legacy_ops" "LegacyOps2024"
echo "T_CAT created and populated."

# -------------------------------------------------------
# Create T_PRD — products (no PK, no FK, no comments)
# -------------------------------------------------------
oracle_query "CREATE TABLE legacy_ops.t_prd (
  prd_id     NUMBER(8),
  prd_nm     VARCHAR2(120),
  cat_id     NUMBER(4),
  unit_prc   NUMBER(10,2),
  stock_qty  NUMBER(8)
)" "legacy_ops" "LegacyOps2024"

oracle_query "INSERT INTO legacy_ops.t_prd VALUES (1001, 'Laptop Pro 15', 1, 1299.99, 45)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_prd VALUES (1002, 'Wireless Mouse', 1, 29.99, 200)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_prd VALUES (1003, 'USB-C Hub 7-port', 1, 49.99, 150)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_prd VALUES (2001, 'A4 Paper Box 5-ream', 2, 24.99, 500)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_prd VALUES (2002, 'Ballpoint Pen Box-50', 2, 8.99, 1000)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_prd VALUES (3001, 'Ergonomic Chair', 3, 399.00, 30)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_prd VALUES (3002, 'Standing Desk Adj', 3, 599.00, 20)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_prd VALUES (4001, 'Database License 1yr', 4, 2499.00, 999)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_prd VALUES (4002, 'Security Suite', 4, 199.00, 999)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_prd VALUES (5001, 'Consulting Hour', 5, 150.00, 9999)" "legacy_ops" "LegacyOps2024"
oracle_query "COMMIT" "legacy_ops" "LegacyOps2024"
echo "T_PRD created and populated."

# -------------------------------------------------------
# Create T_CLI — clients (no PK, no comments)
# -------------------------------------------------------
oracle_query "CREATE TABLE legacy_ops.t_cli (
  cli_id     NUMBER(8),
  cli_nm     VARCHAR2(100),
  cli_email  VARCHAR2(120),
  cli_region VARCHAR2(30),
  cli_since  DATE
)" "legacy_ops" "LegacyOps2024"

# Derive clients from real HR countries and departments
oracle_query "INSERT INTO legacy_ops.t_cli VALUES (1, 'Acme Corporation', 'procurement@acme.example', 'NORTH_AMERICA', DATE '2018-03-15')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_cli VALUES (2, 'GlobalTech Ltd', 'orders@globaltech.example', 'EUROPE', DATE '2019-07-22')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_cli VALUES (3, 'Pacific Rim Trading', 'supply@pacrim.example', 'ASIA_PACIFIC', DATE '2020-01-10')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_cli VALUES (4, 'Meridian Financial', 'ops@meridian.example', 'NORTH_AMERICA', DATE '2017-11-30')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_cli VALUES (5, 'Nordic Systems AB', 'purchase@nordic.example', 'EUROPE', DATE '2021-04-05')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_cli VALUES (6, 'Sahara Logistics', 'buying@sahara.example', 'AFRICA_MIDEAST', DATE '2022-09-18')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_cli VALUES (7, 'Andes Enterprise', 'orders@andes.example', 'LATIN_AMERICA', DATE '2019-02-28')" "legacy_ops" "LegacyOps2024"
oracle_query "COMMIT" "legacy_ops" "LegacyOps2024"
echo "T_CLI created and populated."

# -------------------------------------------------------
# Create T_ORD — orders (no PK, no FK, no comments)
# Data derived from cross of real HR employees and real clients
# -------------------------------------------------------
oracle_query "CREATE TABLE legacy_ops.t_ord (
  ord_id     NUMBER(10),
  cli_id     NUMBER(8),
  emp_id     NUMBER(6),
  ord_dt     DATE,
  ord_amt    NUMBER(12,2),
  ord_status VARCHAR2(20)
)" "legacy_ops" "LegacyOps2024"

# Insert orders using real employee IDs and client IDs
oracle_query "INSERT INTO legacy_ops.t_ord VALUES (10001, 1, 100, DATE '2023-01-15', 3899.97, 'COMPLETED')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord VALUES (10002, 2, 101, DATE '2023-01-22', 2499.00, 'COMPLETED')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord VALUES (10003, 3, 102, DATE '2023-02-03', 599.00, 'COMPLETED')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord VALUES (10004, 4, 103, DATE '2023-02-14', 1499.97, 'COMPLETED')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord VALUES (10005, 5, 104, DATE '2023-03-01', 799.98, 'COMPLETED')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord VALUES (10006, 1, 105, DATE '2023-03-18', 5100.00, 'COMPLETED')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord VALUES (10007, 6, 106, DATE '2023-04-07', 398.00, 'COMPLETED')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord VALUES (10008, 7, 107, DATE '2023-04-22', 2649.99, 'COMPLETED')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord VALUES (10009, 2, 108, DATE '2023-05-10', 1199.97, 'SHIPPED')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord VALUES (10010, 3, 109, DATE '2023-05-28', 4998.00, 'SHIPPED')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord VALUES (10011, 4, 110, DATE '2023-06-12', 349.98, 'PENDING')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord VALUES (10012, 5, 111, DATE '2023-06-30', 1299.99, 'PENDING')" "legacy_ops" "LegacyOps2024"
oracle_query "COMMIT" "legacy_ops" "LegacyOps2024"
echo "T_ORD created and populated."

# -------------------------------------------------------
# Create T_ORD_ITM — order line items (no PK, no FK, no comments)
# -------------------------------------------------------
oracle_query "CREATE TABLE legacy_ops.t_ord_itm (
  itm_id   NUMBER(12),
  ord_id   NUMBER(10),
  prd_id   NUMBER(8),
  qty      NUMBER(6),
  unit_prc NUMBER(10,2),
  line_tot NUMBER(12,2)
)" "legacy_ops" "LegacyOps2024"

oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (1, 10001, 1001, 2, 1299.99, 2599.98)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (2, 10001, 3001, 1, 399.00, 399.00)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (3, 10001, 1002, 3, 29.99, 89.97)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (4, 10002, 4001, 1, 2499.00, 2499.00)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (5, 10003, 3002, 1, 599.00, 599.00)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (6, 10004, 1001, 1, 1299.99, 1299.99)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (7, 10004, 1003, 2, 49.99, 99.98)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (8, 10004, 1002, 1, 29.99, 29.99)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (9, 10005, 4002, 4, 199.00, 796.00)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (10, 10006, 5001, 34, 150.00, 5100.00)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (11, 10007, 3001, 1, 399.00, 399.00)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (12, 10008, 1001, 1, 1299.99, 1299.99)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (13, 10008, 3002, 1, 599.00, 599.00)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (14, 10008, 2001, 30, 24.99, 749.70)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (15, 10009, 2002, 50, 8.99, 449.50)" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_ord_itm VALUES (16, 10009, 2001, 30, 24.99, 749.70)" "legacy_ops" "LegacyOps2024"
oracle_query "COMMIT" "legacy_ops" "LegacyOps2024"
echo "T_ORD_ITM created and populated."

# -------------------------------------------------------
# Create T_LOG — activity audit log (no PK, no FK, no comments)
# -------------------------------------------------------
oracle_query "CREATE TABLE legacy_ops.t_log (
  log_id      NUMBER(12),
  log_dt      DATE,
  entity_type VARCHAR2(20),
  entity_id   NUMBER(12),
  action      VARCHAR2(30),
  usr         VARCHAR2(30)
)" "legacy_ops" "LegacyOps2024"

oracle_query "INSERT INTO legacy_ops.t_log VALUES (1, DATE '2023-01-15', 'ORDER', 10001, 'CREATE', 'EMP100')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_log VALUES (2, DATE '2023-01-15', 'ORDER', 10001, 'APPROVE', 'MANAGER')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_log VALUES (3, DATE '2023-01-22', 'ORDER', 10002, 'CREATE', 'EMP101')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_log VALUES (4, DATE '2023-02-03', 'ORDER', 10003, 'CREATE', 'EMP102')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_log VALUES (5, DATE '2023-03-18', 'ORDER', 10006, 'CREATE', 'EMP105')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_log VALUES (6, DATE '2023-03-19', 'ORDER', 10006, 'MODIFY', 'MANAGER')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_log VALUES (7, DATE '2023-04-10', 'PRODUCT', 1001, 'PRICE_CHANGE', 'ADMIN')" "legacy_ops" "LegacyOps2024"
oracle_query "INSERT INTO legacy_ops.t_log VALUES (8, DATE '2023-05-10', 'ORDER', 10009, 'CREATE', 'EMP108')" "legacy_ops" "LegacyOps2024"
oracle_query "COMMIT" "legacy_ops" "LegacyOps2024"
echo "T_LOG created and populated."

# -------------------------------------------------------
# Record baseline: count of existing comments and constraints
# These should be 0 (no documentation in the legacy schema)
# -------------------------------------------------------
INITIAL_TABLE_COMMENTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_comments WHERE owner='LEGACY_OPS' AND comments IS NOT NULL" "system/OraclePassword123")
INITIAL_COL_COMMENTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_col_comments WHERE owner='LEGACY_OPS' AND comments IS NOT NULL" "system/OraclePassword123")
INITIAL_PK_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints WHERE owner='LEGACY_OPS' AND constraint_type='P'" "system/OraclePassword123")
INITIAL_FK_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints WHERE owner='LEGACY_OPS' AND constraint_type='R'" "system/OraclePassword123")

echo "${INITIAL_TABLE_COMMENTS:-0}" > /tmp/initial_legacy_table_comments
echo "${INITIAL_COL_COMMENTS:-0}" > /tmp/initial_legacy_col_comments
echo "${INITIAL_PK_COUNT:-0}" > /tmp/initial_legacy_pk_count
echo "${INITIAL_FK_COUNT:-0}" > /tmp/initial_legacy_fk_count

echo "Baseline state recorded:"
echo "  Table comments:  ${INITIAL_TABLE_COMMENTS:-0}"
echo "  Column comments: ${INITIAL_COL_COMMENTS:-0}"
echo "  PK constraints:  ${INITIAL_PK_COUNT:-0}"
echo "  FK constraints:  ${INITIAL_FK_COUNT:-0}"

# -------------------------------------------------------
# Configure SQL Developer connection for LEGACY_OPS
# -------------------------------------------------------
CONNECTIONS_FILE="/home/ga/.sqldeveloper/system24.3.0.023.2321/o.jdeveloper.db.connection/connections.json"
mkdir -p "$(dirname $CONNECTIONS_FILE)"

cat > "$CONNECTIONS_FILE" << 'CONNEOF'
{
  "connections": [
    {
      "name": "HR Database",
      "type": "jdbc",
      "info": {
        "customUrl": "jdbc:oracle:thin:@localhost:1521/XEPDB1",
        "SavePassword": "true",
        "driver": "oracle.jdbc.OracleDriver",
        "hostname": "localhost",
        "port": "1521",
        "serviceName": "XEPDB1",
        "user": "hr",
        "password": "hr123",
        "ConnectionType": "TNS"
      }
    },
    {
      "name": "Legacy Ops Schema",
      "type": "jdbc",
      "info": {
        "customUrl": "jdbc:oracle:thin:@localhost:1521/XEPDB1",
        "SavePassword": "true",
        "driver": "oracle.jdbc.OracleDriver",
        "hostname": "localhost",
        "port": "1521",
        "serviceName": "XEPDB1",
        "user": "legacy_ops",
        "password": "LegacyOps2024",
        "ConnectionType": "TNS"
      }
    },
    {
      "name": "System DBA",
      "type": "jdbc",
      "info": {
        "customUrl": "jdbc:oracle:thin:@localhost:1521/XEPDB1",
        "SavePassword": "true",
        "driver": "oracle.jdbc.OracleDriver",
        "hostname": "localhost",
        "port": "1521",
        "serviceName": "XEPDB1",
        "user": "system",
        "password": "OraclePassword123",
        "ConnectionType": "TNS"
      }
    }
  ]
}
CONNEOF

chown -R ga:ga /home/ga/.sqldeveloper 2>/dev/null || true
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports 2>/dev/null || true

# -------------------------------------------------------
# Record task start time
# -------------------------------------------------------
date +%s > /tmp/task_start_timestamp

# -------------------------------------------------------
# Ensure SQL Developer is running
# -------------------------------------------------------
SQLDEVELOPER_PID=$(pgrep -f "sqldeveloper" | head -1)
if [ -z "$SQLDEVELOPER_PID" ]; then
    echo "Starting SQL Developer..."
    sudo -u ga DISPLAY=:1 /opt/sqldeveloper/sqldeveloper.sh &
    sleep 15
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Data Model Reverse Engineering Setup Complete ==="
echo "LEGACY_OPS schema created with 8 undocumented tables."
echo "Tables: T_CLI, T_ORD, T_ORD_ITM, T_PRD, T_CAT, T_EMP, T_DEPT, T_LOG"
echo "No PKs, no FKs, no comments — ready for reverse engineering."
