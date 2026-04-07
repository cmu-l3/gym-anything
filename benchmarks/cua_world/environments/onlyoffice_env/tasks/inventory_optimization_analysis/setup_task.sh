#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Inventory Optimization Analysis Task ==="

# Record task start timestamp for anti-gaming verification
echo $(date +%s) > /tmp/inventory_optimization_start_ts

# Cleanup environment
cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Generate the datasets deterministically
cat > /tmp/generate_inventory_data.py << 'PYEOF'
import csv
import random
from datetime import datetime, timedelta

# Deterministic seed for reproducible testing
random.seed(2024)

# 1. Generate Product Catalog
categories = ["Fasteners", "Electrical", "Plumbing", "Safety", "Hand Tools", "Paint", "Adhesives", "Abrasives"]
products = []
skus = []

for i in range(1, 151):
    sku = f"SKU-{i:03d}"
    cat = random.choice(categories)
    cost = round(random.uniform(0.5, 450.0), 2)
    price = round(cost * random.uniform(1.3, 1.5), 2)  # 30-50% markup
    lead_time = random.randint(5, 45)
    moq = random.choice([1, 5, 10, 50, 100])
    
    skus.append(sku)
    products.append([sku, f"{cat} Item {i}", cat, cost, price, lead_time, moq])

with open('/home/ga/Documents/Spreadsheets/product_catalog.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["sku", "description", "category", "unit_cost", "selling_price", "supplier_lead_time_days", "min_order_qty"])
    writer.writerows(products)

# 2. Generate Transactions
start_date = datetime(2023, 7, 1)
transactions = []
tx_id = 10000

# Pareto weights to simulate ABC demand concentration (top 20% do 80% volume)
weights = [1.0 / (i**1.2) for i in range(1, 151)]

# Select 18 SKUs as "Dead Stock" (no sales in the last 90 days of the dataset)
dead_skus = skus[-18:]
cutoff_date = datetime(2024, 4, 1) # Last 90 days of the year period ending June 30, 2024

for _ in range(2500):
    date = start_date + timedelta(days=random.randint(0, 364))
    sku = random.choices(skus, weights=weights)[0]
    
    # Enforce dead stock condition
    if sku in dead_skus and date >= cutoff_date:
        continue
        
    tx_type = random.choices(["RECEIPT", "SHIPMENT"], weights=[0.2, 0.8])[0]
    
    if tx_type == "SHIPMENT":
        qty = random.randint(1, 50)
        ref = f"SO-{random.randint(10000, 99999)}"
    else:
        qty = random.randint(50, 200)
        ref = f"PO-{random.randint(1000, 9999)}"
        
    transactions.append([tx_id, date.strftime("%Y-%m-%d"), sku, tx_type, qty, ref])
    tx_id += 1

# Sort by date
transactions.sort(key=lambda x: x[1])

with open('/home/ga/Documents/Spreadsheets/inventory_transactions.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["transaction_id", "date", "sku", "transaction_type", "quantity", "reference"])
    writer.writerows(transactions)

# 3. Generate Parameters File
with open('/home/ga/Documents/warehouse_parameters.txt', 'w') as f:
    f.write("PACIFIC COAST DISTRIBUTION - WAREHOUSE PARAMETERS\n")
    f.write("=================================================\n")
    f.write("Target Service Level: 95% (z = 1.65)\n")
    f.write("Annual Carrying Cost Rate: 25%\n")
    f.write("Ordering Cost: $45 per PO\n")
    f.write("Working Days per Year: 252\n")

PYEOF

python3 /tmp/generate_inventory_data.py
chown -R ga:ga "$WORKSPACE_DIR"
chown ga:ga /home/ga/Documents/warehouse_parameters.txt

# Start OnlyOffice spreadsheet editor
echo "Launching ONLYOFFICE..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:cell > /tmp/onlyoffice_launch.log 2>&1 &"

# Wait for window and maximize
wait_for_window "ONLYOFFICE" 30
focus_onlyoffice_window || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture starting state
su - ga -c "DISPLAY=:1 scrot /tmp/inventory_task_initial.png 2>/dev/null" || true

echo "=== Setup Complete ==="