#!/bin/bash
echo "=== Setting up RFM Segmentation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean up any existing ONLYOFFICE instances
kill_onlyoffice ga
cleanup_temp_files
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
CSV_PATH="$WORKSPACE_DIR/online_retail_q4.csv"

# Generate the dataset deterministically
cat > /tmp/generate_rfm_data.py << 'EOF'
import csv
import random
from datetime import datetime, timedelta

# Deterministic seed for reproducible ground truth
random.seed(2024)
ref_date = datetime(2011, 12, 1)

# Generate 380 unique customers
customers = list(range(10001, 10381)) 

with open('/home/ga/Documents/Spreadsheets/online_retail_q4.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['InvoiceNo', 'StockCode', 'Description', 'Quantity', 'InvoiceDate', 'UnitPrice', 'CustomerID', 'Country'])
    
    for i in range(5000):
        # 10% of customers are 'whales' with much higher frequency
        if random.random() < 0.2:
            cust_id = random.choice(customers[:38])
        else:
            cust_id = random.choice(customers)
            
        inv_no = f"5{random.randint(10000, 99999)}"
        stock_code = f"{random.randint(10000, 99999)}{random.choice(['A','B','C',''])}"
        desc = f"PRODUCT {stock_code}"
        qty = random.randint(1, 12)
        
        # Distribute purchases over the 90 days prior to ref_date
        days_ago = random.randint(0, 85)
        inv_date = ref_date - timedelta(days=days_ago)
        
        price = round(random.uniform(1.5, 35.0), 2)
        country = "United Kingdom"
        
        writer.writerow([inv_no, stock_code, desc, qty, inv_date.strftime('%Y-%m-%d'), price, cust_id, country])
EOF

echo "Generating transaction data..."
python3 /tmp/generate_rfm_data.py
chown ga:ga "$CSV_PATH"

# Launch ONLYOFFICE directly opening the CSV
echo "Launching ONLYOFFICE..."
sudo -u ga DISPLAY=:1 /home/ga/launch_spreadsheet.sh "$CSV_PATH"

# Wait for window to appear
wait_for_window "ONLYOFFICE" 30
sleep 5

# Maximize and Focus ONLYOFFICE window
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Handle the CSV import dialog (press Enter to accept default delimiter settings)
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 2
    
    # Re-focus
    focus_window "$WID"
fi

# Take initial screenshot as proof of setup
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="