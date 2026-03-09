#!/bin/bash
set -e
echo "=== Setting up Northwind Freight Optimization Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Directories
DB_DIR="/home/ga/Documents/databases"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"
mkdir -p "$DB_DIR" "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents

# Download Northwind DB if missing
NW_DB="$DB_DIR/northwind.db"
if [ ! -f "$NW_DB" ] || [ "$(stat -c%s "$NW_DB" 2>/dev/null || echo 0)" -lt 10000 ]; then
    echo "Downloading Northwind database..."
    wget -q -O "$NW_DB" "https://raw.githubusercontent.com/jpwhite3/northwind-SQLite3/refs/heads/main/dist/northwind.db" || \
    wget -q -O "$NW_DB" "https://github.com/jpwhite3/northwind-SQLite-3/blob/main/dist/northwind.db?raw=true"
    
    if [ ! -f "$NW_DB" ]; then
        echo "Failed to download database. Creating basic schema for fallback..."
        sqlite3 "$NW_DB" "CREATE TABLE Shippers(ShipperID INTEGER PRIMARY KEY, CompanyName TEXT);"
        sqlite3 "$NW_DB" "CREATE TABLE Orders(OrderID INTEGER PRIMARY KEY, ShipVia INTEGER, Freight REAL, ShipCountry TEXT, ShippedDate TEXT);"
    fi
fi
chmod 644 "$NW_DB"
chown ga:ga "$NW_DB"

# Remove previous artifacts
rm -f "$EXPORT_DIR/routing_guide.csv"
rm -f "$SCRIPTS_DIR/shipping_analysis.sql"
# Drop the view if it exists from previous runs
sqlite3 "$NW_DB" "DROP VIEW IF EXISTS v_country_shipper_stats;" 2>/dev/null || true

# Generate Ground Truth Data (Hidden from agent)
echo "Generating ground truth data..."
python3 << 'PYEOF'
import sqlite3
import json

db_path = "/home/ga/Documents/databases/northwind.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Query to calculate average freight by Country and Shipper
query = """
    SELECT 
        o.ShipCountry, 
        s.CompanyName, 
        AVG(o.Freight) as AvgFreight
    FROM Orders o
    JOIN Shippers s ON o.ShipVia = s.ShipperID
    WHERE o.ShippedDate IS NOT NULL
    GROUP BY o.ShipCountry, s.CompanyName
"""

try:
    rows = cursor.execute(query).fetchall()
    
    # Process in Python
    country_stats = {}
    for r in rows:
        country = r[0]
        shipper = r[1]
        avg_cost = r[2]
        
        if country not in country_stats:
            country_stats[country] = []
        country_stats[country].append({'shipper': shipper, 'cost': avg_cost})
    
    ground_truth = {}
    for country, shippers in country_stats.items():
        # Find min and max
        min_shipper = min(shippers, key=lambda x: x['cost'])
        max_cost = max(s['cost'] for s in shippers)
        savings = max_cost - min_shipper['cost']
        
        ground_truth[country] = {
            'Recommended_Shipper': min_shipper['shipper'],
            'Avg_Cost': round(min_shipper['cost'], 2),
            'Potential_Savings': round(savings, 2)
        }

    with open('/tmp/freight_ground_truth.json', 'w') as f:
        json.dump(ground_truth, f, indent=2)
        
    print(f"Ground truth generated for {len(ground_truth)} countries")

except Exception as e:
    print(f"Error generating ground truth: {e}")
    # Create empty ground truth to prevent crash, verify step will handle failure
    with open('/tmp/freight_ground_truth.json', 'w') as f:
        json.dump({}, f)

conn.close()
PYEOF

# Ensure DBeaver is running
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

# Maximize and Focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "DBeaver" 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="