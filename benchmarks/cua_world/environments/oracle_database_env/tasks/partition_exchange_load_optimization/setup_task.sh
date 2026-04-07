#!/bin/bash
# Setup for Partition Exchange Load Optimization Task
# 1. Downloads Online Retail dataset (or generates realistic fallback)
# 2. Creates partitioned SALES_FACT table
# 3. Loads Jan-Nov 2011 data into SALES_FACT
# 4. Creates SALES_STAGING_DEC11 with Dec 2011 data
# 5. Creates Indexes on SALES_FACT (but NOT on staging)

set -e

echo "=== Setting up Partition Exchange Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/6] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Data Preparation ---
echo "[2/6] Preparing Dataset..."

DATA_FILE="/tmp/online_retail.csv"

# We use a python script to download or generate data
# The Online Retail II dataset is ~20MB-40MB.
python3 << 'PYEOF'
import csv
import random
import datetime
import os

# Try to look for cached file first
if os.path.exists("/opt/datasets/online_retail_II.csv"):
    print("Using cached dataset")
    source_file = "/opt/datasets/online_retail_II.csv"
else:
    # Generate realistic synthetic data if real data download fails/isn't available
    # (Using generation for stability/speed in CI environments while maintaining realism)
    print("Generating realistic retail dataset...")
    
    countries = ['United Kingdom', 'France', 'Germany', 'EIRE', 'Spain']
    descriptions = ['WHITE HANGING HEART T-LIGHT HOLDER', 'WHITE METAL LANTERN', 'CREAM CUPID HEARTS COAT HANGER', 'KNITTED UNION FLAG HOT WATER BOTTLE', 'RED WOOLLY HOTTIE WHITE HEART.']
    
    with open("/tmp/online_retail.csv", "w", newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["InvoiceNo", "StockCode", "Description", "Quantity", "InvoiceDate", "UnitPrice", "CustomerID", "Country"])
        
        # Generate data for Jan - Dec 2011
        start_date = datetime.date(2011, 1, 1)
        end_date = datetime.date(2011, 12, 31)
        delta = end_date - start_date
        
        for i in range(delta.days + 1):
            day = start_date + datetime.timedelta(days=i)
            # Higher volume in December
            num_txns = 300 if day.month == 12 else 100
            
            for _ in range(num_txns):
                inv_no = f"5{random.randint(40000, 80000)}"
                stock = f"22{random.randint(100, 999)}"
                desc = random.choice(descriptions)
                qty = random.randint(1, 20)
                # Oracle default date format often DD-MON-RR, we'll use ISO YYYY-MM-DD for standard loading
                inv_date = day.strftime("%Y-%m-%d")
                price = round(random.uniform(1.0, 15.0), 2)
                cust_id = random.randint(13000, 18000)
                country = random.choice(countries)
                
                writer.writerow([inv_no, stock, desc, qty, inv_date, price, cust_id, country])
PYEOF

# --- Clean up old objects ---
echo "[3/6] Cleaning up old schema objects..."
oracle_query "
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE sales_fact CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE sales_staging_dec11 CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
" "hr" > /dev/null 2>&1

# --- Create Tables ---
echo "[4/6] Creating Tables..."

# Create Partitioned Fact Table
oracle_query "
CREATE TABLE sales_fact (
    invoice_no    VARCHAR2(20),
    stock_code    VARCHAR2(20),
    description   VARCHAR2(255),
    quantity      NUMBER,
    invoice_date  DATE,
    unit_price    NUMBER,
    customer_id   NUMBER,
    country       VARCHAR2(50)
)
PARTITION BY RANGE (invoice_date) (
    PARTITION p_2011_jan VALUES LESS THAN (TO_DATE('2011-02-01', 'YYYY-MM-DD')),
    PARTITION p_2011_feb VALUES LESS THAN (TO_DATE('2011-03-01', 'YYYY-MM-DD')),
    PARTITION p_2011_mar VALUES LESS THAN (TO_DATE('2011-04-01', 'YYYY-MM-DD')),
    PARTITION p_2011_apr VALUES LESS THAN (TO_DATE('2011-05-01', 'YYYY-MM-DD')),
    PARTITION p_2011_may VALUES LESS THAN (TO_DATE('2011-06-01', 'YYYY-MM-DD')),
    PARTITION p_2011_jun VALUES LESS THAN (TO_DATE('2011-07-01', 'YYYY-MM-DD')),
    PARTITION p_2011_jul VALUES LESS THAN (TO_DATE('2011-08-01', 'YYYY-MM-DD')),
    PARTITION p_2011_aug VALUES LESS THAN (TO_DATE('2011-09-01', 'YYYY-MM-DD')),
    PARTITION p_2011_sep VALUES LESS THAN (TO_DATE('2011-10-01', 'YYYY-MM-DD')),
    PARTITION p_2011_oct VALUES LESS THAN (TO_DATE('2011-11-01', 'YYYY-MM-DD')),
    PARTITION p_2011_nov VALUES LESS THAN (TO_DATE('2011-12-01', 'YYYY-MM-DD')),
    PARTITION p_2011_12  VALUES LESS THAN (TO_DATE('2012-01-01', 'YYYY-MM-DD'))
);
" "hr"

# Create Staging Table (Empty for now)
oracle_query "
CREATE TABLE sales_staging_dec11 (
    invoice_no    VARCHAR2(20),
    stock_code    VARCHAR2(20),
    description   VARCHAR2(255),
    quantity      NUMBER,
    invoice_date  DATE,
    unit_price    NUMBER,
    customer_id   NUMBER,
    country       VARCHAR2(50)
);
" "hr"

# --- Load Data ---
echo "[5/6] Loading Data via Python..."
# We use Python for bulk insert because SQL*Loader might be tricky to configure in restricted env
python3 << 'PYEOF'
import csv
import oracledb

conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
cursor = conn.cursor()

batch_fact = []
batch_stage = []

with open("/tmp/online_retail.csv", "r") as f:
    reader = csv.reader(f)
    next(reader) # Skip header
    for row in reader:
        # row: inv_no, stock, desc, qty, date, price, cust, country
        # Date format in CSV is YYYY-MM-DD
        inv_date = row[4]
        
        # Check month
        month = int(inv_date.split('-')[1])
        
        # Prepare tuple
        data = (row[0], row[1], row[2], row[3], inv_date, row[5], row[6], row[7])
        
        if month == 12:
            batch_stage.append(data)
        else:
            batch_fact.append(data)

# Insert Fact Data (Jan-Nov)
if batch_fact:
    print(f"Inserting {len(batch_fact)} rows into SALES_FACT...")
    cursor.executemany("""
        INSERT INTO sales_fact (invoice_no, stock_code, description, quantity, invoice_date, unit_price, customer_id, country)
        VALUES (:1, :2, :3, :4, TO_DATE(:5, 'YYYY-MM-DD'), :6, :7, :8)
    """, batch_fact)

# Insert Staging Data (Dec)
if batch_stage:
    print(f"Inserting {len(batch_stage)} rows into SALES_STAGING_DEC11...")
    cursor.executemany("""
        INSERT INTO sales_staging_dec11 (invoice_no, stock_code, description, quantity, invoice_date, unit_price, customer_id, country)
        VALUES (:1, :2, :3, :4, TO_DATE(:5, 'YYYY-MM-DD'), :6, :7, :8)
    """, batch_stage)

conn.commit()
cursor.close()
conn.close()
PYEOF

# --- Create Indexes on Fact Table ---
echo "[6/6] Creating Indexes..."

# Global Index on Customer ID
oracle_query "CREATE INDEX idx_sales_customer ON sales_fact(customer_id) GLOBAL;" "hr"

# Local Index on Invoice No
oracle_query "CREATE INDEX idx_sales_invoice ON sales_fact(invoice_no) LOCAL;" "hr"

# Record Initial Counts
STAGING_COUNT=$(get_table_count "sales_staging_dec11" "hr")
FACT_DEC_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM sales_fact PARTITION (p_2011_12);" "hr" | tr -d ' ')

echo "Initial Staging Count: $STAGING_COUNT"
echo "Initial Fact Dec Count: $FACT_DEC_COUNT"

echo "$STAGING_COUNT" > /tmp/initial_staging_count.txt
date +%s > /tmp/task_start_time.txt

# Start DBeaver
if ! pgrep -f "dbeaver" > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/bin/dbeaver &"
    sleep 5
fi
DISPLAY=:1 wmctrl -a "DBeaver" 2>/dev/null || true

take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="