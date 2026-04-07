#!/bin/bash
# Setup script for Warehouse Transfer API task
# Creates necessary tables and data in HR schema

set -e
echo "=== Setting up Warehouse Transfer API Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Oracle to be ready
echo "Checking Oracle status..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# 2. Reset Schema (Drop tables/packages if they exist from previous run)
echo "Resetting schema..."
oracle_query "
BEGIN
    BEGIN EXECUTE IMMEDIATE 'DROP PACKAGE inv_manager'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE transfer_log CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE inventory CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE products CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE warehouses CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/" "hr" > /dev/null 2>&1 || true

# 3. Create Tables
echo "Creating tables..."
oracle_query "
CREATE TABLE warehouses (
    wh_id NUMBER PRIMARY KEY,
    location_name VARCHAR2(100)
);

CREATE TABLE products (
    sku VARCHAR2(50) PRIMARY KEY,
    name VARCHAR2(100),
    price NUMBER(10,2)
);

CREATE TABLE inventory (
    sku VARCHAR2(50) REFERENCES products(sku),
    wh_id NUMBER REFERENCES warehouses(wh_id),
    quantity NUMBER,
    PRIMARY KEY (sku, wh_id)
);

CREATE TABLE transfer_log (
    transfer_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku VARCHAR2(50),
    from_wh NUMBER,
    to_wh NUMBER,
    qty NUMBER,
    transfer_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
" "hr" > /dev/null 2>&1

# 4. Populate Data
echo "Populating initial data..."
oracle_query "
-- Warehouses
INSERT INTO warehouses VALUES (1, 'Seattle Distribution Center');
INSERT INTO warehouses VALUES (2, 'Boston Local Hub');
INSERT INTO warehouses VALUES (3, 'Austin Annex');

-- Products
INSERT INTO products VALUES ('SKU-LOGI-MX3', 'Logitech MX Master 3', 99.99);
INSERT INTO products VALUES ('SKU-DELL-XPS', 'Dell XPS 15', 1899.00);
INSERT INTO products VALUES ('SKU-SAM-SSD', 'Samsung 980 Pro 2TB', 149.99);

-- Inventory
-- Note: Warehouse 2 has NO stock of LOGI-MX3 initially (missing row case)
INSERT INTO inventory VALUES ('SKU-LOGI-MX3', 1, 50); -- Seattle has 50
INSERT INTO inventory VALUES ('SKU-DELL-XPS', 1, 10);
INSERT INTO inventory VALUES ('SKU-DELL-XPS', 2, 5);
INSERT INTO inventory VALUES ('SKU-SAM-SSD', 3, 100);

COMMIT;
" "hr" > /dev/null 2>&1

# 5. Record Initial State
date +%s > /tmp/task_start_timestamp
echo "Task setup complete. Tables created. Data loaded."

# 6. Ensure DBeaver is running (for convenience)
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/dbeaver &" > /dev/null 2>&1 &
fi

# 7. Take initial screenshot
sleep 5
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="