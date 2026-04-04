#!/bin/bash
# Setup script for northwind_fraud_detection_benford task

set -e
echo "=== Setting up Northwind Fraud Detection Task ==="

source /workspace/scripts/task_utils.sh

# Directory setup
mkdir -p /home/ga/Documents/databases
mkdir -p /home/ga/Documents/exports
mkdir -p /home/ga/Documents/scripts
chown -R ga:ga /home/ga/Documents

NORTHWIND_DB="/home/ga/Documents/databases/northwind.db"

# Ensure Northwind database exists
if [ ! -f "$NORTHWIND_DB" ] || [ "$(get_file_size "$NORTHWIND_DB")" -lt 10000 ]; then
    echo "Downloading Northwind database..."
    wget -q -O /tmp/northwind.sql "https://raw.githubusercontent.com/jpwhite3/northwind-SQLite3/main/Northwind_large.sql"
    sqlite3 "$NORTHWIND_DB" < /tmp/northwind.sql
    rm -f /tmp/northwind.sql
fi

# Set permissions
chown ga:ga "$NORTHWIND_DB"

# Calculate Ground Truth using Python
# We do this now to verify the DB state and have exact numbers for the verifier
echo "Calculating ground truth..."
python3 << 'PYEOF'
import sqlite3
import json

db_path = "/home/ga/Documents/databases/northwind.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Find the OrderDetails table (handling case sensitivity)
tables = [row[0] for row in c.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
od_table = next((t for t in tables if t.lower().replace('_', '') == 'orderdetails'), None)

if not od_table:
    print("Error: OrderDetails table not found")
    exit(1)

# Fetch all line items to compute digits python-side (most reliable ground truth)
# Formula: UnitPrice * Quantity * (1 - Discount)
query = f"SELECT UnitPrice, Quantity, Discount FROM \"{od_table}\""
rows = c.execute(query).fetchall()

digit_counts = {str(d): 0 for d in range(1, 10)}
total_items = 0

for price, qty, discount in rows:
    # Handle potential NULLs/strings if DB is messy, though Northwind is usually clean
    try:
        p = float(price) if price else 0
        q = float(qty) if qty else 0
        d = float(discount) if discount else 0
        
        line_total = p * q * (1.0 - d)
        
        if line_total > 0:
            # Extract first non-zero digit
            # Convert to string, remove decimal point, strip leading zeros
            s = f"{line_total:.10f}".replace('.', '').lstrip('0')
            if s:
                first_digit = s[0]
                if first_digit in digit_counts:
                    digit_counts[first_digit] += 1
                    total_items += 1
    except Exception as e:
        continue

# Calculate proportions
ground_truth = {
    "digit_counts": digit_counts,
    "total_count": total_items,
    "digit_props": {k: round(v/total_items, 4) if total_items else 0 for k, v in digit_counts.items()}
}

with open('/tmp/benford_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)

print(f"Ground truth calculated. Total items: {total_items}")
PYEOF

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for DBeaver to start
    for i in {1..30}; do
        if is_dbeaver_running; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Focus DBeaver and maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="