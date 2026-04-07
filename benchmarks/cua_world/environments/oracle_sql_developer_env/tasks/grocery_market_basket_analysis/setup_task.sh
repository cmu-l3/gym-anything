#!/bin/bash
# Setup script for Grocery Market Basket Analysis task
echo "=== Setting up Grocery Market Basket Analysis Task ==="

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
  EXECUTE IMMEDIATE 'DROP USER grocery_bi CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

rm -f /home/ga/Documents/exports/market_basket_top200.csv
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

sleep 2

# ---------------------------------------------------------------
# 3. Create GROCERY_BI schema
# ---------------------------------------------------------------
echo "Creating GROCERY_BI schema..."

oracle_query "CREATE USER grocery_bi IDENTIFIED BY Grocery2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO grocery_bi;
GRANT RESOURCE TO grocery_bi;
GRANT CREATE VIEW TO grocery_bi;
GRANT CREATE MATERIALIZED VIEW TO grocery_bi;
GRANT CREATE PROCEDURE TO grocery_bi;
GRANT CREATE SESSION TO grocery_bi;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create grocery_bi user"
    exit 1
fi

# ---------------------------------------------------------------
# 4. Create Tables and Deterministic Seed Data
# ---------------------------------------------------------------
echo "Creating tables and seeding 10,000 orders (this takes ~10s)..."

sudo docker exec -i oracle-xe sqlplus -s grocery_bi/Grocery2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE departments (
    department_id NUMBER PRIMARY KEY,
    department_name VARCHAR2(100)
);

CREATE TABLE aisles (
    aisle_id NUMBER PRIMARY KEY,
    aisle_name VARCHAR2(100)
);

CREATE TABLE products (
    product_id NUMBER PRIMARY KEY,
    product_name VARCHAR2(100),
    aisle_id NUMBER,
    department_id NUMBER
);

CREATE TABLE orders (
    order_id NUMBER PRIMARY KEY,
    user_id NUMBER,
    order_dow NUMBER,
    order_hour_of_day NUMBER,
    days_since_prior_order NUMBER
);

CREATE TABLE order_products (
    order_id NUMBER REFERENCES orders(order_id),
    product_id NUMBER REFERENCES products(product_id),
    add_to_cart_order NUMBER,
    PRIMARY KEY (order_id, product_id)
);

-- PL/SQL block to populate exactly 10,000 orders with predictable associations
DECLARE
  v_order_id NUMBER := 1000;
BEGIN
  -- Insert 100 products
  FOR i IN 1..100 LOOP
    INSERT INTO products (product_id, product_name, aisle_id, department_id) 
    VALUES (i, 'Product ' || i, 1, 1);
  END LOOP;
  
  -- Name our specific test targets
  UPDATE products SET product_name = 'Hot Dogs' WHERE product_id = 1;
  UPDATE products SET product_name = 'Hot Dog Buns' WHERE product_id = 2;
  UPDATE products SET product_name = 'Peanut Butter' WHERE product_id = 3;
  UPDATE products SET product_name = 'Jelly' WHERE product_id = 4;

  -- Insert exactly 10,000 orders
  FOR i IN 1..10000 LOOP
    INSERT INTO orders (order_id, user_id, order_dow) VALUES (i, MOD(i, 1000), MOD(i, 7));
  END LOOP;

  -- Test Pair 1: Hot Dogs (1) & Buns (2)
  -- Total orders = 10000
  -- 400 orders have both
  -- 100 orders have just Hot Dogs -> Total Support A = 500
  -- 200 orders have just Buns -> Total Support B = 600
  -- Math: Supp(A)=0.05, Supp(B)=0.06, Supp(A,B)=0.04
  -- Conf(A->B) = 0.04/0.05 = 0.8
  -- Conf(B->A) = 0.04/0.06 = 0.6667
  -- Lift = 0.04 / (0.05 * 0.06) = 13.3333
  FOR i IN 1..400 LOOP
    INSERT INTO order_products (order_id, product_id, add_to_cart_order) VALUES (i, 1, 1);
    INSERT INTO order_products (order_id, product_id, add_to_cart_order) VALUES (i, 2, 2);
  END LOOP;
  FOR i IN 401..500 LOOP
    INSERT INTO order_products (order_id, product_id, add_to_cart_order) VALUES (i, 1, 1);
  END LOOP;
  FOR i IN 501..700 LOOP
    INSERT INTO order_products (order_id, product_id, add_to_cart_order) VALUES (i, 2, 1);
  END LOOP;

  -- Test Pair 2: Peanut Butter (3) & Jelly (4)
  -- 100 together, 50 only PB, 50 only Jelly
  -- Supp(A)=150 (0.015), Supp(B)=150 (0.015), Supp(A,B)=100 (0.010)
  -- Lift = 0.010 / (0.015 * 0.015) = 44.4444
  -- Conf(A->B) = 0.010/0.015 = 0.6667
  FOR i IN 701..800 LOOP
    INSERT INTO order_products (order_id, product_id, add_to_cart_order) VALUES (i, 3, 1);
    INSERT INTO order_products (order_id, product_id, add_to_cart_order) VALUES (i, 4, 2);
  END LOOP;
  FOR i IN 801..850 LOOP
    INSERT INTO order_products (order_id, product_id, add_to_cart_order) VALUES (i, 3, 1);
  END LOOP;
  FOR i IN 851..900 LOOP
    INSERT INTO order_products (order_id, product_id, add_to_cart_order) VALUES (i, 4, 1);
  END LOOP;

  -- Generate 250+ other valid pairs to ensure the CSV has 200 rows meeting constraints
  -- constraints: pair_count >= 20 and lift > 2.0
  -- Products 10 through 50 (40 items). Pair each with 6 others -> 240 pairs.
  -- Give each pair exactly 25 co-occurrences.
  FOR a IN 10..50 LOOP
    FOR b IN (a+1)..(a+6) LOOP
       FOR k IN 1..25 LOOP
          v_order_id := v_order_id + 1;
          BEGIN
            INSERT INTO order_products (order_id, product_id) VALUES (v_order_id, a);
            INSERT INTO order_products (order_id, product_id) VALUES (v_order_id, b);
          EXCEPTION WHEN OTHERS THEN NULL; END;
       END LOOP;
    END LOOP;
  END LOOP;

  COMMIT;
END;
/
EXIT;
EOSQL

echo "Database seeded with 10,000 orders."

# ---------------------------------------------------------------
# 5. Pre-configure GUI connection
# ---------------------------------------------------------------
ensure_hr_connection "Grocery DB" "grocery_bi" "Grocery2024"

# Launch SQL Developer
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    echo "Starting SQL Developer..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
            echo "SQL Developer window detected"
            break
        fi
        sleep 1
    done
fi

DISPLAY=:1 wmctrl -r "Oracle SQL Developer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Oracle SQL Developer" 2>/dev/null || true

# Open connection
open_hr_connection_in_sqldeveloper

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="