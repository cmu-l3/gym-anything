#!/bin/bash
# Setup script for Retail SCD2 Dimension Modeling task
echo "=== Setting up Retail SCD2 Dimension Modeling ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

echo "Setting up RETAIL_DW schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER retail_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# Create schema and grant privileges
oracle_query "CREATE USER retail_admin IDENTIFIED BY Retail2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO retail_admin;
GRANT RESOURCE TO retail_admin;
GRANT CREATE VIEW TO retail_admin;
GRANT CREATE PROCEDURE TO retail_admin;
GRANT CREATE TRIGGER TO retail_admin;
GRANT CREATE SESSION TO retail_admin;
GRANT CREATE SEQUENCE TO retail_admin;
EXIT;" "system"

# Create Database Objects
echo "Creating tables and sequences..."
sudo docker exec -i oracle-xe sqlplus -s retail_admin/Retail2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE SEQUENCE seq_product_key START WITH 10000 INCREMENT BY 1 NOCACHE;

CREATE TABLE source_products (
    product_id NUMBER PRIMARY KEY,
    sku VARCHAR2(50),
    name VARCHAR2(150),
    category VARCHAR2(50),
    unit_price NUMBER(10,2),
    status VARCHAR2(20),
    last_updated DATE
);

CREATE TABLE dim_products (
    product_key NUMBER PRIMARY KEY,
    product_id NUMBER,
    sku VARCHAR2(50),
    name VARCHAR2(150),
    category VARCHAR2(50),
    unit_price NUMBER(10,2),
    status VARCHAR2(20),
    valid_from DATE,
    valid_to DATE,
    is_current CHAR(1)
);

CREATE TABLE sales_fact (
    sale_id NUMBER PRIMARY KEY,
    product_id NUMBER,
    sale_date DATE,
    quantity NUMBER,
    discount_pct NUMBER(5,2)
);

-- Seed Data: 1000 SmartHome products in SOURCE only
BEGIN
  FOR i IN 1..1000 LOOP
    INSERT INTO source_products (product_id, sku, name, category, unit_price, status, last_updated)
    VALUES (i, 'SH-'||i, 'Smart Product '||i, 'SmartHome', ROUND(DBMS_RANDOM.VALUE(10, 500), 2), 'ACTIVE', SYSDATE-30);
  END LOOP;
  COMMIT;
END;
/

-- Seed Data: Electronics products in BOTH source and dim
BEGIN
  FOR i IN 8000..8010 LOOP
    INSERT INTO source_products VALUES (i, 'EL-'||i, 'Elec '||i, 'Electronics', 100.00, 'ACTIVE', SYSDATE-100);
    INSERT INTO dim_products VALUES (seq_product_key.NEXTVAL, i, 'EL-'||i, 'Elec '||i, 'Electronics', 100.00, 'ACTIVE', TO_DATE('2020-01-01', 'YYYY-MM-DD'), TO_DATE('9999-12-31', 'YYYY-MM-DD'), 'Y');
  END LOOP;
  COMMIT;
END;
/

-- Seed Data: Anomalies with overlapping dates
BEGIN
  FOR i IN 9001..9005 LOOP
    INSERT INTO source_products VALUES (i, 'AN-'||i, 'Anom '||i, 'Anomaly', 50.00, 'ACTIVE', SYSDATE);
    INSERT INTO dim_products VALUES (seq_product_key.NEXTVAL, i, 'AN-'||i, 'Anom '||i, 'Anomaly', 40.00, 'ACTIVE', TO_DATE('2021-01-01', 'YYYY-MM-DD'), TO_DATE('2023-01-01', 'YYYY-MM-DD'), 'N');
    INSERT INTO dim_products VALUES (seq_product_key.NEXTVAL, i, 'AN-'||i, 'Anom '||i, 'Anomaly', 50.00, 'ACTIVE', TO_DATE('2022-06-01', 'YYYY-MM-DD'), TO_DATE('9999-12-31', 'YYYY-MM-DD'), 'Y');
  END LOOP;
  COMMIT;
END;
/

-- Seed Data: Sales fact test record
INSERT INTO sales_fact VALUES (1, 8000, TO_DATE('2022-01-01', 'YYYY-MM-DD'), 2, 0);
COMMIT;
EXIT;
EOSQL

echo "Database objects and seed data created."

# Configure SQL Developer connection
ensure_hr_connection "Retail DW" "retail_admin" "Retail2024"

# Open the connection in SQL Developer
open_hr_connection_in_sqldeveloper

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="