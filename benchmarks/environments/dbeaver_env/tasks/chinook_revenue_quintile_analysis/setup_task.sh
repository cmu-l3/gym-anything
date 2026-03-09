#!/bin/bash
# Setup script for chinook_revenue_quintile_analysis
# Ensures DBeaver is running and calculates ground truth for verification

echo "=== Setting up Revenue Quintile Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Remove previous artifacts
rm -f "$EXPORT_DIR/revenue_quintiles.csv"
rm -f "$SCRIPTS_DIR/quintile_analysis.sql"

# Calculate Ground Truth using Python/SQLite
# We calculate what the Top 20% (Quintile 1) revenue should be
echo "Calculating ground truth..."
python3 << 'PYEOF'
import sqlite3
import json

try:
    conn = sqlite3.connect("/home/ga/Documents/databases/chinook.db")
    cursor = conn.cursor()
    
    # 1. Calculate total spend per customer
    cursor.execute("SELECT CustomerId, SUM(Total) as Spend FROM invoices GROUP BY CustomerId ORDER BY Spend DESC")
    customers = cursor.fetchall() # list of (id, spend)
    
    total_customers = len(customers)
    total_revenue = sum(c[1] for c in customers)
    
    # 2. Simulate NTILE(5)
    # SQLite NTILE distributes rows as evenly as possible.
    # If 59 customers, 59 % 5 = 4 remainder.
    # The first 4 buckets get size+1.
    # Sizes: 12, 12, 12, 12, 11
    
    bucket_size = total_customers // 5
    remainder = total_customers % 5
    
    quintiles = {}
    current_idx = 0
    
    for q in range(1, 6):
        size = bucket_size + (1 if q <= remainder else 0)
        chunk = customers[current_idx : current_idx + size]
        current_idx += size
        
        q_revenue = sum(c[1] for c in chunk)
        q_count = len(chunk)
        
        quintiles[q] = {
            "count": q_count,
            "revenue": q_revenue,
            "avg": q_revenue / q_count if q_count > 0 else 0
        }

    ground_truth = {
        "total_customers": total_customers,
        "global_revenue": total_revenue,
        "quintile_1": quintiles[1],
        "quintile_5": quintiles[5]
    }
    
    with open('/tmp/quintile_gt.json', 'w') as f:
        json.dump(ground_truth, f)
        
    print(f"Ground Truth Calculated: Q1 Revenue = {quintiles[1]['revenue']:.2f}")

except Exception as e:
    print(f"Error calculating ground truth: {e}")
    # Fallback default values if calculation fails
    with open('/tmp/quintile_gt.json', 'w') as f:
        json.dump({"quintile_1": {"revenue": 880.0}}, f)
PYEOF

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure DBeaver is running and maximized
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="