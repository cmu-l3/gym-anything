#!/bin/bash
set -e
echo "=== Setting up Northwind Schema Reconstruction Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Documents/databases
mkdir -p /home/ga/Documents/imports
mkdir -p /home/ga/Documents/exports
mkdir -p /home/ga/Documents/scripts
chown -R ga:ga /home/ga/Documents

# Clean up any previous run artifacts
rm -f /home/ga/Documents/databases/northwind_restored.db
rm -f /home/ga/Documents/exports/restoration_check.csv

# 1. Prepare Source Data (Real Northwind DB)
# We download the standard Northwind SQLite DB to a temp location to generate the CSV
echo "Acquiring Northwind data..."
WGET_URL="https://raw.githubusercontent.com/jpwhite3/northwind-SQLite3/main/Northwind_large.sql"
TEMP_SQL="/tmp/northwind_source.sql"
TEMP_DB="/tmp/northwind_source.db"

# Download SQL dump if not present
if [ ! -f "$TEMP_SQL" ]; then
    wget -q -O "$TEMP_SQL" "$WGET_URL" || \
    curl -L -o "$TEMP_SQL" "$WGET_URL"
fi

# Create temp DB
rm -f "$TEMP_DB"
if [ -f "$TEMP_SQL" ]; then
    echo "Creating temporary source database..."
    sqlite3 "$TEMP_DB" < "$TEMP_SQL"
else
    echo "ERROR: Failed to download Northwind source."
    exit 1
fi

# 2. Generate the "Legacy Sales Dump" CSV
# We flatten Orders, Customers, Products, and OrderDetails
CSV_PATH="/home/ga/Documents/imports/legacy_sales_dump.csv"
echo "Generating flat CSV dump to $CSV_PATH..."

# Note: Table names in jpwhite3/northwind-SQLite3 are PascalCase but 'Order Details' has a space
sqlite3 -header -csv "$TEMP_DB" "
SELECT 
    o.Id as LegacyOrderID,
    o.OrderDate,
    c.CompanyName as CustomerName,
    c.Country,
    p.ProductName,
    cat.CategoryName,
    od.UnitPrice,
    od.Quantity,
    od.Discount
FROM 'Order' o
JOIN Customer c ON o.CustomerId = c.Id
JOIN 'OrderDetail' od ON o.Id = od.OrderId
JOIN Product p ON od.ProductId = p.Id
JOIN Category cat ON p.CategoryId = cat.Id
ORDER BY o.OrderDate;
" > "$CSV_PATH" 2>/dev/null || \
sqlite3 -header -csv "$TEMP_DB" "
SELECT 
    o.OrderID as LegacyOrderID,
    o.OrderDate,
    c.CompanyName as CustomerName,
    c.Country,
    p.ProductName,
    cat.CategoryName,
    od.UnitPrice,
    od.Quantity,
    od.Discount
FROM Orders o
JOIN Customers c ON o.CustomerID = c.CustomerID
JOIN 'Order Details' od ON o.OrderID = od.OrderID
JOIN Products p ON od.ProductID = p.ProductID
JOIN Categories cat ON p.CategoryID = cat.CategoryID
ORDER BY o.OrderDate;
" > "$CSV_PATH"

# Verify CSV generation
LINE_COUNT=$(wc -l < "$CSV_PATH")
echo "Generated CSV with $LINE_COUNT lines."
chown ga:ga "$CSV_PATH"

if [ "$LINE_COUNT" -lt 100 ]; then
    echo "ERROR: CSV generation failed or data is too small."
    exit 1
fi

# Save ground truth counts for verification
echo "$LINE_COUNT" > /tmp/ground_truth_csv_lines.txt

# Clean up source DB (Agent shouldn't use it directly)
rm -f "$TEMP_DB" "$TEMP_SQL"

# 3. Setup DBeaver
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "dbeaver"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize Window
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="