#!/bin/bash
# Setup script for northwind_territory_performance task
# Downloads the Northwind database and computes ground truth

set -e
echo "=== Setting up Northwind Territory Performance Task ==="

source /workspace/scripts/task_utils.sh

NORTHWIND_DB="/home/ga/Documents/databases/northwind.db"
DB_DIR="/home/ga/Documents/databases"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$DB_DIR" "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Remove any pre-existing output files (clean state)
rm -f "$EXPORT_DIR/territory_report.csv"
rm -f "$SCRIPTS_DIR/territory_analysis.sql"

# Download Northwind database if not present
if [ ! -f "$NORTHWIND_DB" ] || [ "$(stat -c%s "$NORTHWIND_DB" 2>/dev/null || echo 0)" -lt 10000 ]; then
    echo "Downloading Northwind database..."

    # Try downloading the pre-built SQLite binary directly
    NORTHWIND_DOWNLOADED=false

    # Primary: try the large SQL file and create SQLite from it
    if wget -q --timeout=60 "https://raw.githubusercontent.com/jpwhite3/northwind-SQLite3/main/Northwind_large.sql" \
        -O /tmp/northwind_large.sql 2>/dev/null && [ -s /tmp/northwind_large.sql ]; then
        echo "Downloaded Northwind SQL. Creating SQLite database..."
        sqlite3 "$NORTHWIND_DB" < /tmp/northwind_large.sql && NORTHWIND_DOWNLOADED=true
        rm -f /tmp/northwind_large.sql
    fi

    # Fallback: try alternate raw URL
    if [ "$NORTHWIND_DOWNLOADED" = "false" ]; then
        echo "Trying alternate Northwind source..."
        wget -q --timeout=60 "https://raw.githubusercontent.com/jpwhite3/northwind-SQLite3/refs/heads/main/Northwind_large.sql" \
            -O /tmp/northwind_large.sql 2>/dev/null && \
        sqlite3 "$NORTHWIND_DB" < /tmp/northwind_large.sql && NORTHWIND_DOWNLOADED=true
        rm -f /tmp/northwind_large.sql
    fi

    if [ "$NORTHWIND_DOWNLOADED" = "false" ] || [ ! -f "$NORTHWIND_DB" ] || [ "$(stat -c%s "$NORTHWIND_DB" 2>/dev/null || echo 0)" -lt 10000 ]; then
        echo "ERROR: Failed to download Northwind database"
        exit 1
    fi

    chown ga:ga "$NORTHWIND_DB"
    echo "Northwind database created at $NORTHWIND_DB"
else
    echo "Northwind database already present"
fi

# Verify the database is valid and has expected tables
echo "Verifying Northwind database..."
TABLES=$(sqlite3 "$NORTHWIND_DB" ".tables" 2>/dev/null)
echo "Tables found: $TABLES"

if ! echo "$TABLES" | grep -qi "territories"; then
    echo "ERROR: Northwind database missing Territories table"
    exit 1
fi

if ! echo "$TABLES" | grep -qi "orders"; then
    echo "ERROR: Northwind database missing Orders table"
    exit 1
fi

# Compute ground truth territory revenue using the correct query
echo "Computing territory performance ground truth..."
python3 << 'PYEOF'
import sqlite3
import json
import sys

db_path = "/home/ga/Documents/databases/northwind.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

# First, detect the actual table and column names (case may vary)
tables = [row[0] for row in c.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
print(f"Tables: {tables}")

# Find the OrderDetails table (may be 'OrderDetails' or 'Order Details')
orderdetails_table = None
for t in tables:
    if t.replace(' ', '').replace('_','').lower() == 'orderdetails':
        orderdetails_table = t
        break

if not orderdetails_table:
    print("ERROR: Cannot find OrderDetails table", file=sys.stderr)
    sys.exit(1)

print(f"Using OrderDetails table: '{orderdetails_table}'")

# Get column names for orders table
orders_cols = [row[1] for row in c.execute("PRAGMA table_info(Orders)").fetchall()]
print(f"Orders columns: {orders_cols}")

# Detect EmployeeTerritories table
empterr_table = None
for t in tables:
    if 'employeeterrit' in t.replace(' ', '').replace('_', '').lower():
        empterr_table = t
        break

if not empterr_table:
    print("ERROR: Cannot find EmployeeTerritories table", file=sys.stderr)
    sys.exit(1)

print(f"EmployeeTerritories table: '{empterr_table}'")

# Build the ground truth query
query = f"""
SELECT
    t.TerritoryID,
    TRIM(t.TerritoryDescription) as TerritoryDescription,
    TRIM(r.RegionDescription) as RegionDescription,
    ROUND(SUM(od.Quantity * od.UnitPrice * (1.0 - od.Discount)), 2) as TotalRevenue,
    COUNT(DISTINCT o.OrderID) as OrderCount,
    ROUND(SUM(od.Quantity * od.UnitPrice * (1.0 - od.Discount)) /
          NULLIF(COUNT(DISTINCT o.OrderID), 0), 2) as AvgOrderValue,
    COUNT(DISTINCT e.EmployeeID) as EmployeeCount
FROM Orders o
JOIN Employees e ON o.EmployeeID = e.EmployeeID
JOIN "{empterr_table}" et ON e.EmployeeID = et.EmployeeID
JOIN Territories t ON et.TerritoryID = t.TerritoryID
JOIN Region r ON t.RegionID = r.RegionID
JOIN "{orderdetails_table}" od ON o.OrderID = od.OrderID
GROUP BY t.TerritoryID
ORDER BY TotalRevenue DESC
"""

try:
    rows = c.execute(query).fetchall()
    print(f"Territory count: {len(rows)}")

    if not rows:
        print("ERROR: Query returned no results", file=sys.stderr)
        sys.exit(1)

    top5 = [{'territory_id': str(r[0]), 'description': r[1], 'region': r[2],
              'revenue': r[3], 'orders': r[4]} for r in rows[:5]]
    bottom5 = [{'territory_id': str(r[0]), 'description': r[1], 'region': r[2],
                 'revenue': r[3], 'orders': r[4]} for r in rows[-5:]]

    ground_truth = {
        'territory_count': len(rows),
        'top_territory_id': str(rows[0][0]),
        'top_territory_revenue': rows[0][3],
        'top_territory_description': rows[0][1],
        'top5': top5,
        'bottom5': bottom5,
        'total_revenue': round(sum(r[3] for r in rows), 2),
        'orderdetails_table': orderdetails_table,
        'empterritories_table': empterr_table
    }

    with open('/tmp/northwind_territory_gt.json', 'w') as f:
        json.dump(ground_truth, f, indent=2)

    print(f"Ground truth saved. Top territory: {rows[0][1]} (${rows[0][3]:,.2f})")
except Exception as e:
    print(f"ERROR computing ground truth: {e}", file=sys.stderr)
    sys.exit(1)
finally:
    conn.close()
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Ground truth computation failed"
    exit 1
fi

# Record baseline state
INITIAL_TERRITORY_CSV_EXISTS="false"
if [ -f "$EXPORT_DIR/territory_report.csv" ]; then
    INITIAL_TERRITORY_CSV_EXISTS="true"
fi
echo "$INITIAL_TERRITORY_CSV_EXISTS" > /tmp/initial_territory_csv

# Check initial DBeaver connections
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
INITIAL_CONN_COUNT=0
if [ -f "$DBEAVER_CONFIG" ]; then
    INITIAL_CONN_COUNT=$(python3 -c "
import json
try:
    with open('$DBEAVER_CONFIG') as f:
        config = json.load(f)
    print(len(config.get('connections', {})))
except:
    print(0)
" 2>/dev/null || echo 0)
fi
echo "$INITIAL_CONN_COUNT" > /tmp/initial_dbeaver_conn_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task started at: $(date)"

# Ensure DBeaver is running and focused
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 dbeaver &" 2>/dev/null &
    sleep 8
fi
focus_dbeaver || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/northwind_task_start.png
echo "=== Northwind Territory Setup Complete ==="
