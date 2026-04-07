#!/bin/bash
# Setup script for Sales Interval Partitioning task
# Generates synthetic sales data CSV and ensures database is clean

set -e

echo "=== Setting up Sales Interval Partitioning Task ==="

source /workspace/scripts/task_utils.sh

# --- 1. Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- 2. Clean up previous artifacts ---
echo "[2/4] Cleaning up previous task artifacts..."
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE global_sales CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true

rm -f /home/ga/Desktop/sales_data_raw.csv
rm -f /home/ga/Desktop/partition_structure.txt

# --- 3. Generate Sales Data CSV ---
echo "[3/4] Generating sales data CSV..."
python3 << 'PYEOF'
import csv
import random
from datetime import date, timedelta
import os

file_path = "/home/ga/Desktop/sales_data_raw.csv"
regions = ['NA', 'EU', 'AS', 'SA']

# Ensure directory exists
os.makedirs(os.path.dirname(file_path), exist_ok=True)

print(f"Generating {file_path}...")
with open(file_path, 'w', newline='') as f:
    writer = csv.writer(f)
    # Header
    writer.writerow(['TRANS_ID', 'SALE_DATE', 'REGION_CODE', 'AMOUNT', 'CUSTOMER_ID'])
    
    start_date = date(2024, 1, 1)
    # Generate ~2000 rows
    for i in range(2000):
        # Random date within 2 years
        day_offset = random.randint(0, 730)
        txn_date = start_date + timedelta(days=day_offset)
        
        # Weighted regions
        region = random.choices(regions, weights=[40, 30, 20, 10], k=1)[0]
        
        # Amount
        amount = round(random.uniform(10.0, 5000.0), 2)
        
        # Customer ID
        cust_id = random.randint(1000, 9999)
        
        writer.writerow([i+1, txn_date.strftime('%Y-%m-%d'), region, amount, cust_id])

print("CSV generation complete.")
PYEOF

# Ensure user owns the file
chown ga:ga /home/ga/Desktop/sales_data_raw.csv
chmod 644 /home/ga/Desktop/sales_data_raw.csv

# --- 4. Record Start State ---
echo "[4/4] Recording initial state..."
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Data file: /home/ga/Desktop/sales_data_raw.csv"