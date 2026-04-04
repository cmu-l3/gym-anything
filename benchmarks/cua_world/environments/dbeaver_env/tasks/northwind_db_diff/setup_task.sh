#!/bin/bash
# Setup script for northwind_db_diff task
# Creates Prod and Staging databases with specific differences

set -e
echo "=== Setting up Northwind DB Diff Task ==="

source /workspace/scripts/task_utils.sh

DB_DIR="/home/ga/Documents/databases"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$DB_DIR" "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Clean up previous run
rm -f "$DB_DIR/northwind_prod.db" "$DB_DIR/northwind_staging.db"
rm -f "$EXPORT_DIR/db_diff_report.csv"
rm -f "$SCRIPTS_DIR/sync_prod_to_staging.sql"

# 1. Download Base Northwind Database
BASE_DB="/tmp/northwind_base.db"
if [ ! -f "$BASE_DB" ]; then
    echo "Downloading base Northwind database..."
    wget -q --timeout=60 "https://raw.githubusercontent.com/jpwhite3/northwind-SQLite3/main/Northwind_large.sql" -O /tmp/nw.sql
    sqlite3 "$BASE_DB" < /tmp/nw.sql
    rm -f /tmp/nw.sql
fi

# 2. Create Production DB (Clean Copy)
echo "Creating Production DB..."
cp "$BASE_DB" "$DB_DIR/northwind_prod.db"

# 3. Create Staging DB (Modified Copy)
echo "Creating Staging DB..."
cp "$BASE_DB" "$DB_DIR/northwind_staging.db"

# 4. Apply Differences to Staging DB
echo "Applying changes to Staging DB..."
sqlite3 "$DB_DIR/northwind_staging.db" <<EOF
-- Product INSERTs (3 rows)
INSERT INTO Product (Id, ProductName, SupplierId, CategoryId, UnitPrice, Discontinued) VALUES (78, 'Organic Honey Spread', 1, 2, 28.50, 0);
INSERT INTO Product (Id, ProductName, SupplierId, CategoryId, UnitPrice, Discontinued) VALUES (79, 'Artisan Rye Bread', 2, 5, 12.75, 0);
INSERT INTO Product (Id, ProductName, SupplierId, CategoryId, UnitPrice, Discontinued) VALUES (80, 'Highland Spring Water', 3, 1, 4.50, 0);

-- Product UnitPrice UPDATEs (5 rows)
UPDATE Product SET UnitPrice = 19.50 WHERE Id = 1;  -- Was 18.00
UPDATE Product SET UnitPrice = 21.00 WHERE Id = 2;  -- Was 19.00
UPDATE Product SET UnitPrice = 5.25 WHERE Id = 24;  -- Was 4.50
UPDATE Product SET UnitPrice = 275.00 WHERE Id = 38; -- Was 263.50
UPDATE Product SET UnitPrice = 49.99 WHERE Id = 43;  -- Was 46.00

-- Customer DELETEs (2 rows)
DELETE FROM Customer WHERE Id = 'CENTC';
DELETE FROM Customer WHERE Id = 'FISSA';

-- Category INSERT (1 row)
INSERT INTO Category (Id, CategoryName, Description) VALUES (9, 'Organic', 'Certified organic food products');

-- OrderDetail Quantity UPDATEs (4 rows)
-- Note: OrderDetail PK is composite, usually handled via rowid or explicit match in WHERE
UPDATE OrderDetail SET Quantity = 15 WHERE OrderId = 10248 AND ProductId = 11; -- Was 12
UPDATE OrderDetail SET Quantity = 8 WHERE OrderId = 10248 AND ProductId = 42;  -- Was 10
UPDATE OrderDetail SET Quantity = 12 WHERE OrderId = 10249 AND ProductId = 14;  -- Was 9
UPDATE OrderDetail SET Quantity = 35 WHERE OrderId = 10249 AND ProductId = 51;  -- Was 40
EOF

# Set permissions
chown ga:ga "$DB_DIR/northwind_prod.db"
chown ga:ga "$DB_DIR/northwind_staging.db"

# 5. Create Ground Truth Data for Verifier
# (Hidden from agent)
cat > /var/lib/dbeaver_task_ground_truth.json <<EOF
{
  "product_inserts": [78, 79, 80],
  "product_updates": [1, 2, 24, 38, 43],
  "customer_deletes": ["CENTC", "FISSA"],
  "category_inserts": [9],
  "orderdetail_updates": [
    {"OrderId": 10248, "ProductId": 11},
    {"OrderId": 10248, "ProductId": 42},
    {"OrderId": 10249, "ProductId": 14},
    {"OrderId": 10249, "ProductId": 51}
  ]
}
EOF

# 6. Record Initial State
date +%s > /tmp/task_start_time.txt
echo "Prod Hash: $(md5sum "$DB_DIR/northwind_prod.db" | awk '{print $1}')" > /tmp/initial_hashes.txt

# Ensure DBeaver is running
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

focus_dbeaver
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="