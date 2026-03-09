#!/bin/bash
set -e
echo "=== Setting up Chinook Dynamic Pricing Task ==="

source /workspace/scripts/task_utils.sh

# Define paths
DB_SOURCE="/home/ga/Documents/databases/chinook.db"
DB_TARGET="/home/ga/Documents/databases/chinook_pricing.db"
GROUND_TRUTH_DIR="/var/lib/dbeaver/ground_truth"

# Ensure directories exist
mkdir -p "$(dirname "$DB_TARGET")"
mkdir -p "/home/ga/Documents/exports"
mkdir -p "/home/ga/Documents/scripts"
mkdir -p "$GROUND_TRUTH_DIR"

# Copy database to create a fresh workspace
if [ -f "$DB_SOURCE" ]; then
    cp "$DB_SOURCE" "$DB_TARGET"
    chown ga:ga "$DB_TARGET"
    chmod 644 "$DB_TARGET"
    echo "Created working database: $DB_TARGET"
else
    echo "ERROR: Source database not found at $DB_SOURCE"
    exit 1
fi

# ------------------------------------------------------------------
# CALCULATE GROUND TRUTH (Hidden from agent)
# ------------------------------------------------------------------
echo "Calculating ground truth..."

# Create a python script to compute expected prices and summary logic
cat > /tmp/compute_gt.py << 'EOF'
import sqlite3
import json
import os

db_path = "/home/ga/Documents/databases/chinook_pricing.db"
gt_file = "/var/lib/dbeaver/ground_truth/pricing_gt.json"

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
c = conn.cursor()

# 1. Get Purchase Counts per Track
# We need left join to include tracks with 0 purchases
query_counts = """
SELECT 
    t.TrackId, 
    t.UnitPrice as OldPrice,
    t.Milliseconds,
    COUNT(ii.InvoiceLineId) as PurchaseCount
FROM tracks t
LEFT JOIN invoice_items ii ON t.TrackId = ii.TrackId
GROUP BY t.TrackId
"""

tracks_gt = {}
tiers_summary = {
    "Platinum": {"count": 0, "sum_new": 0.0, "sum_old": 0.0, "revenue_impact": 0.0},
    "Gold":     {"count": 0, "sum_new": 0.0, "sum_old": 0.0, "revenue_impact": 0.0},
    "Standard": {"count": 0, "sum_new": 0.0, "sum_old": 0.0, "revenue_impact": 0.0},
    "Discount": {"count": 0, "sum_new": 0.0, "sum_old": 0.0, "revenue_impact": 0.0}
}

rows = c.execute(query_counts).fetchall()
for row in rows:
    tid = row["TrackId"]
    count = row["PurchaseCount"]
    ms = row["Milliseconds"]
    old_price = float(row["OldPrice"])
    
    # Determine Tier
    if count >= 5:
        tier = "Platinum"
        base_price = 1.49
    elif count >= 2:
        tier = "Gold"
        base_price = 1.29
    elif count == 1:
        tier = "Standard"
        base_price = 0.99
    else:
        tier = "Discount"
        base_price = 0.79
        
    # Apply Surcharge
    surcharge = 0.30 if ms > 500000 else 0.0
    new_price = round(base_price + surcharge, 2)
    
    # Store track expectation
    tracks_gt[tid] = {
        "tier": tier,
        "old_price": old_price,
        "new_price": new_price
    }
    
    # Update summary
    tiers_summary[tier]["count"] += 1
    tiers_summary[tier]["sum_new"] += new_price
    tiers_summary[tier]["sum_old"] += old_price
    tiers_summary[tier]["revenue_impact"] += (new_price - old_price)

# Finalize summary averages
summary_list = []
for tier, data in tiers_summary.items():
    cnt = data["count"]
    if cnt > 0:
        avg_new = round(data["sum_new"] / cnt, 2)
        avg_old = round(data["sum_old"] / cnt, 2)
    else:
        avg_new = 0.0
        avg_old = 0.0
        
    summary_list.append({
        "Tier": tier,
        "TrackCount": cnt,
        "AvgNewPrice": avg_new,
        "AvgOldPrice": avg_old,
        "RevenueImpact": round(data["revenue_impact"], 2)
    })

output = {
    "tracks": tracks_gt,
    "summary": summary_list
}

with open(gt_file, 'w') as f:
    json.dump(output, f)

conn.close()
EOF

# Execute ground truth calculation
python3 /tmp/compute_gt.py

# Secure the ground truth file
chmod 600 "$GROUND_TRUTH_DIR/pricing_gt.json"
chown root:root "$GROUND_TRUTH_DIR/pricing_gt.json" # Agent cannot read this

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start DBeaver
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "dbeaver"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_dbeaver

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="