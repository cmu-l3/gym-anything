#!/bin/bash
# Setup script for Supply Chain Inventory Rebalance task
echo "=== Setting up Supply Chain Inventory Rebalance ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# ---------------------------------------------------------------
# 1. Verify Oracle is running and HR schema is accessible
# ---------------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

HR_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM hr.employees;" "system" | tr -d '[:space:]')
if [ -z "$HR_CHECK" ] || [ "$HR_CHECK" = "ERROR" ] || [ "$HR_CHECK" -lt 1 ] 2>/dev/null; then
    echo "ERROR: HR schema not loaded or inaccessible"
    exit 1
fi
echo "HR schema verified ($HR_CHECK employees)"

# ---------------------------------------------------------------
# 2. Clean up previous run artifacts (idempotent re-runs)
# ---------------------------------------------------------------
echo "Cleaning up previous run artifacts..."

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER sc_manager CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# 3. Create SUPPLY_CHAIN schema with sc_manager user
# ---------------------------------------------------------------
echo "Creating SUPPLY_CHAIN schema (sc_manager user)..."

oracle_query "CREATE USER sc_manager IDENTIFIED BY Supply2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO sc_manager;
GRANT RESOURCE TO sc_manager;
GRANT CREATE VIEW TO sc_manager;
GRANT CREATE MATERIALIZED VIEW TO sc_manager;
GRANT CREATE PROCEDURE TO sc_manager;
GRANT CREATE JOB TO sc_manager;
GRANT CREATE SESSION TO sc_manager;
GRANT CREATE TABLE TO sc_manager;
GRANT CREATE TYPE TO sc_manager;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create sc_manager user"
    exit 1
fi
echo "sc_manager user created with required privileges"

# ---------------------------------------------------------------
# 4. Create sequences (before tables that reference them)
# ---------------------------------------------------------------
echo "Creating sequences..."

sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE SEQUENCE demand_seq     START WITH 1     INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE inventory_seq  START WITH 1     INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE param_seq      START WITH 1     INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE alert_seq      START WITH 1     INCREMENT BY 1 NOCACHE;

EXIT;
EOSQL
echo "  Sequences created"

# ---------------------------------------------------------------
# 5. Create tables under SUPPLY_CHAIN schema
# ---------------------------------------------------------------
echo "Creating SUPPLY_CHAIN schema tables..."

# -- WAREHOUSES table
sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE warehouses (
    warehouse_id       NUMBER         PRIMARY KEY,
    warehouse_name     VARCHAR2(100)  NOT NULL,
    city               VARCHAR2(100)  NOT NULL,
    state              VARCHAR2(2)    NOT NULL,
    region             VARCHAR2(50)   NOT NULL,
    capacity_units     NUMBER         NOT NULL,
    operating_cost_daily NUMBER(10,2) NOT NULL
);

EXIT;
EOSQL
echo "  WAREHOUSES table created"

# -- PRODUCT_CATEGORIES table
sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE product_categories (
    category_id    NUMBER         PRIMARY KEY,
    category_name  VARCHAR2(100)  NOT NULL,
    hs_code        VARCHAR2(10)   NOT NULL,
    description    VARCHAR2(500)
);

EXIT;
EOSQL
echo "  PRODUCT_CATEGORIES table created"

# -- PRODUCTS table
sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE products (
    product_id     NUMBER         PRIMARY KEY,
    sku            VARCHAR2(20)   UNIQUE NOT NULL,
    product_name   VARCHAR2(200)  NOT NULL,
    category_id    NUMBER         REFERENCES product_categories(category_id),
    unit_cost      NUMBER(10,2)   NOT NULL,
    unit_price     NUMBER(10,2)   NOT NULL,
    weight_lbs     NUMBER(8,2),
    is_active      NUMBER(1)      DEFAULT 1
);

EXIT;
EOSQL
echo "  PRODUCTS table created"

# -- INVENTORY table
sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE inventory (
    inventory_id     NUMBER         PRIMARY KEY,
    warehouse_id     NUMBER         REFERENCES warehouses(warehouse_id),
    product_id       NUMBER         REFERENCES products(product_id),
    on_hand_qty      NUMBER         NOT NULL,
    reserved_qty     NUMBER         DEFAULT 0,
    last_count_date  DATE,
    shelf_location   VARCHAR2(20)
);

EXIT;
EOSQL
echo "  INVENTORY table created"

# -- INVENTORY_PARAMS table
sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE inventory_params (
    param_id          NUMBER         PRIMARY KEY,
    product_id        NUMBER         REFERENCES products(product_id),
    warehouse_id      NUMBER         REFERENCES warehouses(warehouse_id),
    reorder_point     NUMBER         NOT NULL,
    safety_stock      NUMBER         NOT NULL,
    reorder_quantity  NUMBER         NOT NULL,
    lead_time_days    NUMBER         NOT NULL,
    ordering_cost     NUMBER(10,2)   DEFAULT 50.00,
    holding_cost_pct  NUMBER(5,4)    DEFAULT 0.2500,
    service_level     NUMBER(5,4)    DEFAULT 0.9750
);

EXIT;
EOSQL
echo "  INVENTORY_PARAMS table created"

# -- DEMAND_HISTORY table (composite partitioned)
sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE demand_history (
    demand_id          NUMBER         PRIMARY KEY,
    product_id         NUMBER         REFERENCES products(product_id),
    warehouse_id       NUMBER         REFERENCES warehouses(warehouse_id),
    week_start_date    DATE           NOT NULL,
    quantity_demanded  NUMBER         NOT NULL,
    quantity_fulfilled NUMBER         NOT NULL,
    stockout_flag      NUMBER(1)      DEFAULT 0
)
PARTITION BY RANGE (week_start_date)
SUBPARTITION BY LIST (warehouse_id)
(
    PARTITION p_q1_2024 VALUES LESS THAN (DATE '2024-04-01') (
        SUBPARTITION p_q1_wh1 VALUES (1),
        SUBPARTITION p_q1_wh2 VALUES (2),
        SUBPARTITION p_q1_wh3 VALUES (3),
        SUBPARTITION p_q1_wh4 VALUES (4),
        SUBPARTITION p_q1_wh5 VALUES (5)
    ),
    PARTITION p_q2_2024 VALUES LESS THAN (DATE '2024-07-01') (
        SUBPARTITION p_q2_wh1 VALUES (1),
        SUBPARTITION p_q2_wh2 VALUES (2),
        SUBPARTITION p_q2_wh3 VALUES (3),
        SUBPARTITION p_q2_wh4 VALUES (4),
        SUBPARTITION p_q2_wh5 VALUES (5)
    ),
    PARTITION p_q3_2024 VALUES LESS THAN (DATE '2024-10-01') (
        SUBPARTITION p_q3_wh1 VALUES (1),
        SUBPARTITION p_q3_wh2 VALUES (2),
        SUBPARTITION p_q3_wh3 VALUES (3),
        SUBPARTITION p_q3_wh4 VALUES (4),
        SUBPARTITION p_q3_wh5 VALUES (5)
    ),
    PARTITION p_q4_2024 VALUES LESS THAN (DATE '2025-01-01') (
        SUBPARTITION p_q4_wh1 VALUES (1),
        SUBPARTITION p_q4_wh2 VALUES (2),
        SUBPARTITION p_q4_wh3 VALUES (3),
        SUBPARTITION p_q4_wh4 VALUES (4),
        SUBPARTITION p_q4_wh5 VALUES (5)
    )
);

EXIT;
EOSQL
echo "  DEMAND_HISTORY table created (composite partitioned)"

# -- INVENTORY_ALERTS table
sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE inventory_alerts (
    alert_id               NUMBER         PRIMARY KEY,
    product_id             NUMBER,
    warehouse_id           NUMBER,
    alert_type             VARCHAR2(50),
    alert_message          VARCHAR2(500),
    projected_stockout_date DATE,
    created_date           DATE           DEFAULT SYSDATE,
    resolved               NUMBER(1)      DEFAULT 0
);

EXIT;
EOSQL
echo "  INVENTORY_ALERTS table created"

# ---------------------------------------------------------------
# 6. Insert warehouse data (5 real US distribution hub cities)
# ---------------------------------------------------------------
echo "Inserting warehouse data..."

sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

INSERT INTO warehouses (warehouse_id, warehouse_name, city, state, region, capacity_units, operating_cost_daily)
VALUES (1, 'East Coast DC', 'Edison', 'NJ', 'NORTHEAST', 50000, 2500.00);

INSERT INTO warehouses (warehouse_id, warehouse_name, city, state, region, capacity_units, operating_cost_daily)
VALUES (2, 'Southeast DC', 'Atlanta', 'GA', 'SOUTHEAST', 45000, 2200.00);

INSERT INTO warehouses (warehouse_id, warehouse_name, city, state, region, capacity_units, operating_cost_daily)
VALUES (3, 'Midwest DC', 'Chicago', 'IL', 'MIDWEST', 55000, 2400.00);

INSERT INTO warehouses (warehouse_id, warehouse_name, city, state, region, capacity_units, operating_cost_daily)
VALUES (4, 'Southwest DC', 'Dallas', 'TX', 'SOUTHWEST', 40000, 2100.00);

INSERT INTO warehouses (warehouse_id, warehouse_name, city, state, region, capacity_units, operating_cost_daily)
VALUES (5, 'West Coast DC', 'Ontario', 'CA', 'WEST', 60000, 2800.00);

COMMIT;
EXIT;
EOSQL
echo "  5 warehouses inserted"

# ---------------------------------------------------------------
# 7. Insert product categories with HS commodity codes
# ---------------------------------------------------------------
echo "Inserting product categories..."

sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

INSERT INTO product_categories (category_id, category_name, hs_code, description)
VALUES (1, 'Consumer Electronics', '8471', 'Computers and peripherals');

INSERT INTO product_categories (category_id, category_name, hs_code, description)
VALUES (2, 'Household Appliances', '8516', 'Electric heating and cooking appliances');

INSERT INTO product_categories (category_id, category_name, hs_code, description)
VALUES (3, 'Personal Care', '3304', 'Beauty and skincare products');

INSERT INTO product_categories (category_id, category_name, hs_code, description)
VALUES (4, 'Office Supplies', '4820', 'Paper stationery products');

INSERT INTO product_categories (category_id, category_name, hs_code, description)
VALUES (5, 'Sporting Goods', '9506', 'Sports and fitness equipment');

COMMIT;
EXIT;
EOSQL
echo "  5 product categories inserted"

# ---------------------------------------------------------------
# 8. Insert 25 products (5 per category)
# ---------------------------------------------------------------
echo "Inserting products..."

sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- Category 1: Consumer Electronics
INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (1, 'ELEC-WM-001', 'Wireless Mouse', 1, 12.50, 24.99, 0.25);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (2, 'ELEC-UH-002', 'USB-C Hub', 1, 18.00, 39.99, 0.35);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (3, 'ELEC-WC-003', 'Webcam', 1, 22.00, 49.99, 0.50);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (4, 'ELEC-KB-004', 'Keyboard', 1, 15.00, 34.99, 1.20);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (5, 'ELEC-MS-005', 'Monitor Stand', 1, 25.00, 54.99, 3.50);

-- Category 2: Household Appliances
INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (6, 'APPL-CM-006', 'Coffee Maker', 2, 28.00, 59.99, 5.00);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (7, 'APPL-TS-007', 'Toaster', 2, 15.00, 32.99, 3.50);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (8, 'APPL-EK-008', 'Electric Kettle', 2, 12.00, 27.99, 2.50);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (9, 'APPL-BL-009', 'Blender', 2, 20.00, 44.99, 4.00);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (10, 'APPL-AF-010', 'Air Fryer', 2, 35.00, 79.99, 8.00);

-- Category 3: Personal Care
INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (11, 'CARE-FM-011', 'Face Moisturizer', 3, 5.00, 14.99, 0.50);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (12, 'CARE-SS-012', 'Sunscreen SPF50', 3, 4.00, 12.99, 0.40);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (13, 'CARE-HD-013', 'Hair Dryer', 3, 18.00, 39.99, 1.80);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (14, 'CARE-ET-014', 'Electric Toothbrush', 3, 8.00, 22.99, 0.60);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (15, 'CARE-SH-015', 'Shampoo Set', 3, 6.00, 16.99, 1.50);

-- Category 4: Office Supplies
INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (16, 'OFFC-LP-016', 'Legal Pads 12pk', 4, 3.00, 8.99, 2.00);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (17, 'OFFC-BP-017', 'Ballpoint Pens 24pk', 4, 4.00, 11.99, 0.80);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (18, 'OFFC-FF-018', 'File Folders 50pk', 4, 5.00, 14.99, 3.00);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (19, 'OFFC-DO-019', 'Desk Organizer', 4, 7.00, 18.99, 2.50);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (20, 'OFFC-WM-020', 'Whiteboard Markers 8pk', 4, 3.50, 9.99, 0.50);

-- Category 5: Sporting Goods
INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (21, 'SPRT-YM-021', 'Yoga Mat', 5, 8.00, 24.99, 3.00);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (22, 'SPRT-RB-022', 'Resistance Bands Set', 5, 6.00, 17.99, 1.00);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (23, 'SPRT-JR-023', 'Jump Rope', 5, 4.00, 12.99, 0.50);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (24, 'SPRT-FR-024', 'Foam Roller', 5, 10.00, 29.99, 2.00);

INSERT INTO products (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs)
VALUES (25, 'SPRT-WB-025', 'Water Bottle', 5, 5.00, 15.99, 0.75);

COMMIT;
EXIT;
EOSQL
echo "  25 products inserted"

# ---------------------------------------------------------------
# 9. Insert INVENTORY data (125 rows: each product x each warehouse)
# ---------------------------------------------------------------
echo "Inserting inventory data..."

sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

DECLARE
    v_inv_id   NUMBER := 0;
    v_on_hand  NUMBER;
    v_shelf    VARCHAR2(20);
BEGIN
    FOR p IN 1..25 LOOP
        FOR w IN 1..5 LOOP
            v_inv_id := v_inv_id + 1;

            -- On-hand qty varies by product category
            v_on_hand := CASE
                WHEN p <= 5  THEN ROUND(200 + DBMS_RANDOM.VALUE(0, 800))    -- Electronics: 200-1000
                WHEN p <= 10 THEN ROUND(100 + DBMS_RANDOM.VALUE(0, 400))    -- Appliances: 100-500
                WHEN p <= 15 THEN ROUND(500 + DBMS_RANDOM.VALUE(0, 1500))   -- Personal Care: 500-2000
                WHEN p <= 20 THEN ROUND(800 + DBMS_RANDOM.VALUE(0, 1200))   -- Office: 800-2000
                ELSE              ROUND(300 + DBMS_RANDOM.VALUE(0, 700))    -- Sporting: 300-1000
            END;

            v_shelf := CHR(64 + w) || '-' || LPAD(TO_CHAR(p), 2, '0') || '-' || LPAD(TO_CHAR(ROUND(DBMS_RANDOM.VALUE(1,20))), 2, '0');

            INSERT INTO inventory (inventory_id, warehouse_id, product_id, on_hand_qty, reserved_qty, last_count_date, shelf_location)
            VALUES (v_inv_id, w, p, v_on_hand, ROUND(v_on_hand * 0.05), DATE '2024-12-15' + ROUND(DBMS_RANDOM.VALUE(0,15)), v_shelf);
        END LOOP;
    END LOOP;
    COMMIT;
END;
/

EXIT;
EOSQL
echo "  125 inventory rows inserted"

# ---------------------------------------------------------------
# 10. Insert INVENTORY_PARAMS with INJECTED ERRORS
# ---------------------------------------------------------------
echo "Inserting inventory parameters (with injected errors)..."

sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

DECLARE
    v_param_id         NUMBER := 0;
    v_base_demand      NUMBER;
    v_lead_time        NUMBER;
    v_safety_stock     NUMBER;
    v_reorder_point    NUMBER;
    v_reorder_qty      NUMBER;
    v_annual_demand    NUMBER;
    v_unit_cost        NUMBER;
    v_ordering_cost    NUMBER := 50.00;
    v_holding_cost_pct NUMBER := 0.25;
    v_stddev           NUMBER;
    v_is_error1        BOOLEAN;
    v_is_error2        BOOLEAN;
    v_is_error3        BOOLEAN;
BEGIN
    FOR p IN 1..25 LOOP
        -- Get unit cost for EOQ calculation
        SELECT unit_cost INTO v_unit_cost FROM products WHERE product_id = p;

        FOR w IN 1..5 LOOP
            v_param_id := v_param_id + 1;

            -- Base weekly demand by category
            v_base_demand := CASE
                WHEN p <= 5  THEN 100   -- Electronics
                WHEN p <= 10 THEN 75    -- Appliances
                WHEN p <= 15 THEN 200   -- Personal Care
                WHEN p <= 20 THEN 250   -- Office
                ELSE              120   -- Sporting
            END;

            -- Lead time by category (days)
            v_lead_time := CASE
                WHEN p <= 5  THEN 7    -- Electronics: domestic suppliers
                WHEN p <= 10 THEN 14   -- Appliances: some international
                WHEN p <= 15 THEN 5    -- Personal Care: fast replenishment
                WHEN p <= 20 THEN 3    -- Office: readily available
                ELSE              10   -- Sporting: moderate lead time
            END;

            -- Standard deviation ~ 30% of base demand
            v_stddev := v_base_demand * 0.30;

            -- Safety stock = z * stddev * sqrt(lead_time)  where z=1.96 for 97.5% service
            v_safety_stock := ROUND(1.96 * v_stddev * SQRT(v_lead_time));

            -- Reorder point = avg_daily_demand * lead_time + safety_stock
            -- (weekly demand / 7) * lead_time + safety_stock
            v_reorder_point := ROUND((v_base_demand / 7) * v_lead_time + v_safety_stock);

            -- Annual demand
            v_annual_demand := v_base_demand * 52;

            -- EOQ = sqrt(2 * D * S / (C * h))
            v_reorder_qty := ROUND(SQRT(2 * v_annual_demand * v_ordering_cost / (v_unit_cost * v_holding_cost_pct)));

            -- Check for ERROR TYPE 1: Zero reorder points
            -- Products 1,5,8 in warehouses 1,2,3,4
            v_is_error1 := (p IN (1, 5, 8)) AND (w IN (1, 2, 3, 4));

            -- Check for ERROR TYPE 2: Excessive safety stock
            -- Products 10,15 in warehouses 1,2,3,4
            v_is_error2 := (p IN (10, 15)) AND (w IN (1, 2, 3, 4));

            -- Check for ERROR TYPE 3: Zero lead time
            -- Products 20,21,22,23,24 in warehouse 5
            v_is_error3 := (p IN (20, 21, 22, 23, 24)) AND (w = 5);

            -- Apply errors
            IF v_is_error1 THEN
                v_reorder_point := 0;
            END IF;

            IF v_is_error2 THEN
                v_safety_stock := v_base_demand * 52;  -- Full year supply as safety stock
            END IF;

            IF v_is_error3 THEN
                v_lead_time := 0;
            END IF;

            INSERT INTO inventory_params (param_id, product_id, warehouse_id, reorder_point, safety_stock, reorder_quantity, lead_time_days, ordering_cost, holding_cost_pct, service_level)
            VALUES (v_param_id, p, w, v_reorder_point, v_safety_stock, v_reorder_qty, v_lead_time, v_ordering_cost, v_holding_cost_pct, 0.9750);
        END LOOP;
    END LOOP;
    COMMIT;
END;
/

EXIT;
EOSQL
echo "  125 inventory params inserted (with 25 injected errors)"

# ---------------------------------------------------------------
# 11. Insert DEMAND_HISTORY (52 weeks x 25 products x 5 warehouses)
# ---------------------------------------------------------------
echo "Inserting demand history data (6500 rows)..."

sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

DECLARE
    v_base     NUMBER;
    v_seasonal NUMBER;
    v_demand   NUMBER;
    v_week     DATE;
    v_fulfilled NUMBER;
    v_stockout  NUMBER;
BEGIN
    FOR p IN 1..25 LOOP
        FOR w IN 1..5 LOOP
            -- Base demand depends on product category
            v_base := CASE
                WHEN p <= 5  THEN 80 + DBMS_RANDOM.VALUE(0, 40)    -- Electronics
                WHEN p <= 10 THEN 60 + DBMS_RANDOM.VALUE(0, 30)    -- Appliances
                WHEN p <= 15 THEN 150 + DBMS_RANDOM.VALUE(0, 100)  -- Personal Care
                WHEN p <= 20 THEN 200 + DBMS_RANDOM.VALUE(0, 150)  -- Office
                ELSE              100 + DBMS_RANDOM.VALUE(0, 50)   -- Sporting
            END;

            FOR wk IN 0..51 LOOP
                v_week := DATE '2024-01-01' + (wk * 7);

                -- Seasonal factor
                v_seasonal := CASE
                    WHEN EXTRACT(MONTH FROM v_week) IN (11, 12) THEN 1.4
                    WHEN EXTRACT(MONTH FROM v_week) IN (1, 2)   THEN 1.1
                    WHEN EXTRACT(MONTH FROM v_week) IN (4, 5)   THEN 0.85
                    ELSE 1.0
                END;

                v_demand := ROUND(v_base * v_seasonal * (0.8 + DBMS_RANDOM.VALUE(0, 0.4)));

                -- Simulate stockouts for products with zero reorder points (error type 1)
                -- Products 1,5,8 occasionally can't fulfill demand
                IF (p IN (1, 5, 8)) AND (DBMS_RANDOM.VALUE(0, 1) < 0.15) THEN
                    v_fulfilled := ROUND(v_demand * (0.5 + DBMS_RANDOM.VALUE(0, 0.3)));
                    v_stockout := 1;
                ELSE
                    v_fulfilled := v_demand;
                    v_stockout := 0;
                END IF;

                INSERT INTO demand_history (demand_id, product_id, warehouse_id, week_start_date, quantity_demanded, quantity_fulfilled, stockout_flag)
                VALUES (demand_seq.NEXTVAL, p, w, v_week, v_demand, v_fulfilled, v_stockout);
            END LOOP;
        END LOOP;
    END LOOP;
    COMMIT;
END;
/

EXIT;
EOSQL
echo "  Demand history data inserted"

# ---------------------------------------------------------------
# 12. Verify data counts
# ---------------------------------------------------------------
echo "Verifying data counts..."

sudo docker exec -i oracle-xe sqlplus -s sc_manager/Supply2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200

SELECT 'WAREHOUSES: '          || COUNT(*) FROM warehouses;
SELECT 'PRODUCT_CATEGORIES: '  || COUNT(*) FROM product_categories;
SELECT 'PRODUCTS: '            || COUNT(*) FROM products;
SELECT 'INVENTORY: '           || COUNT(*) FROM inventory;
SELECT 'INVENTORY_PARAMS: '    || COUNT(*) FROM inventory_params;
SELECT 'DEMAND_HISTORY: '      || COUNT(*) FROM demand_history;

SELECT 'ERROR TYPE 1 (zero reorder point): ' || COUNT(*) FROM inventory_params WHERE reorder_point = 0;
SELECT 'ERROR TYPE 2 (excessive safety stock): ' || COUNT(*) FROM inventory_params WHERE safety_stock > 3000;
SELECT 'ERROR TYPE 3 (zero lead time): ' || COUNT(*) FROM inventory_params WHERE lead_time_days = 0;
SELECT 'STOCKOUT EVENTS: ' || COUNT(*) FROM demand_history WHERE stockout_flag = 1;

EXIT;
EOSQL

# ---------------------------------------------------------------
# 13. Pre-configure SQL Developer connection for sc_manager
# ---------------------------------------------------------------
echo "Configuring SQL Developer connection..."

ensure_hr_connection "Supply Chain DB" "sc_manager" "Supply2024"

# ---------------------------------------------------------------
# 14. Ensure SQL Developer is running
# ---------------------------------------------------------------
echo "Checking SQL Developer..."

if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    echo "Starting SQL Developer..."
    DISPLAY=:1 nohup /opt/sqldeveloper/sqldeveloper.sh &>/dev/null &
    sleep 15
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
        echo "SQL Developer started successfully"
    else
        echo "WARNING: SQL Developer may not have started"
    fi
else
    echo "SQL Developer is already running"
fi

# ---------------------------------------------------------------
# 15. Take initial screenshot
# ---------------------------------------------------------------
echo "Taking initial screenshot..."
sleep 2
take_screenshot /tmp/setup_complete.png
echo "Screenshot saved to /tmp/setup_complete.png"

echo ""
echo "=== Supply Chain Inventory Rebalance setup complete ==="
echo "Schema: SUPPLY_CHAIN (user: sc_manager / Supply2024)"
echo "Tables: warehouses, product_categories, products, inventory, inventory_params, demand_history, inventory_alerts"
echo "Data: 5 warehouses, 5 categories, 25 products, 125 inventory rows, 125 params, ~6500 demand history rows"
echo "Injected errors: 12 zero reorder points, 8 excessive safety stock, 5 zero lead times"
