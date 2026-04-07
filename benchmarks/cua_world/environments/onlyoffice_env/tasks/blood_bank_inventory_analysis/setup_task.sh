#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Blood Bank Inventory Analysis Task ==="

# Record task start timestamp for anti-gaming
TASK_START=$(date +%s)
echo $TASK_START > /tmp/task_start_time.txt

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/rbc_inventory_raw.csv"
GT_PATH="/var/lib/app/ground_truth_blood_bank.json"
sudo mkdir -p /var/lib/app

# Generate realistic blood bank inventory dataset
cat > /tmp/create_blood_bank_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import sys
import random
import json
from datetime import datetime, timedelta

output_csv = sys.argv[1]
output_gt = sys.argv[2]

# Realistic US blood type distribution
blood_types = [
    ("O+", 0.38), ("A+", 0.34), ("B+", 0.09), ("O-", 0.07),
    ("A-", 0.06), ("AB+", 0.03), ("B-", 0.02), ("AB-", 0.01)
]
types, weights = zip(*blood_types)

# Fixed seed for deterministic output
random.seed(2024)

# Generate 800 RBC units
anchor_date = datetime(2024, 10, 24)
rows = []
gt_counts = {t: 0 for t in types}

# Headers
rows.append(["DIN", "Collection_Date", "Blood_Group", "Product_Code", "Volume_mL"])

for i in range(800):
    # ISBT 128 format DIN: W0000 24 123456 (Facility Code, Year, Serial)
    serial = f"{random.randint(100000, 999999)}"
    din = f"W2104 24 {serial}"
    
    # Collection date: uniformly distributed over the last 45 days
    # (So some will be expired (>42 days), some expiring soon (<=5 days remaining), most fine)
    days_ago = random.randint(1, 45)
    coll_date = anchor_date - timedelta(days=days_ago)
    
    # Blood group
    bg = random.choices(types, weights=weights, k=1)[0]
    gt_counts[bg] += 1
    
    # Product code
    prod_code = "E0404"  # standard code for RBCs, AS-1, leukoreduced
    vol = random.randint(280, 360)
    
    rows.append([din, coll_date.strftime("%Y-%m-%d"), bg, prod_code, vol])

# Write CSV
with open(output_csv, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(rows)

# Write Ground Truth
with open(output_gt, 'w') as f:
    json.dump({
        "total_units": 800,
        "blood_type_counts": gt_counts,
        "anchor_date": "2024-10-24"
    }, f)

print(f"Generated {len(rows)-1} records.")
PYEOF

python3 /tmp/create_blood_bank_data.py "$CSV_PATH" "$GT_PATH"
chown ga:ga "$CSV_PATH"
chmod 644 "$CSV_PATH"

# Start ONLYOFFICE with the CSV file
echo "Launching ONLYOFFICE Spreadsheet Editor..."
sudo -u ga DISPLAY=:1 /usr/bin/onlyoffice-desktopeditors "$CSV_PATH" > /tmp/onlyoffice_launch.log 2>&1 &
sleep 6

# Maximize and focus the window
echo "Configuring window..."
WID=$(DISPLAY=:1 wmctrl -l | grep -i "onlyoffice\|desktopeditors" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 2
    
    # Dismiss any CSV import dialog with Enter
    sudo -u ga DISPLAY=:1 xdotool key Return
    sleep 2
    
    # Re-maximize and focus
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
sudo -u ga DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    sudo -u ga DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="