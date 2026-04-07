#!/bin/bash
# Setup script for financial_grouping_sets_report
# Generates realistic sales data and creates the reference "inefficient" query file.

set -e

echo "=== Setting up Financial Grouping Sets Report Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_timestamp
chmod 644 /tmp/task_start_timestamp

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Generate Sales Data ---
echo "[2/4] Generating realistic sales data..."

# Python script to generate SQL inserts
cat << 'PYEOF' > /tmp/gen_sales.py
import random
import datetime

regions = ['North', 'South', 'East', 'West']
categories = ['Electronics', 'Furniture', 'Office Supplies', 'Software']
start_date = datetime.date(2023, 1, 1)

with open("/tmp/sales_data.sql", "w") as f:
    f.write("SET DEFINE OFF;\n")
    f.write("DROP TABLE sales_transactions PURGE;\n")
    f.write("""
    CREATE TABLE sales_transactions (
        trans_id NUMBER PRIMARY KEY,
        trans_date DATE,
        region VARCHAR2(20),
        category VARCHAR2(30),
        amount NUMBER(10,2)
    );
    """)
    f.write("BEGIN\n")
    
    # Generate 2500 transactions
    for i in range(1, 2501):
        r = random.choice(regions)
        c = random.choice(categories)
        days = random.randint(0, 364)
        d = start_date + datetime.timedelta(days=days)
        d_str = d.strftime("%Y-%m-%d")
        
        # Weighted amounts
        if c == 'Electronics':
            amt = round(random.uniform(200, 5000), 2)
        elif c == 'Furniture':
            amt = round(random.uniform(100, 1500), 2)
        elif c == 'Software':
            amt = round(random.uniform(50, 500), 2)
        else:
            amt = round(random.uniform(10, 200), 2)
            
        f.write(f"  INSERT INTO sales_transactions VALUES ({i}, TO_DATE('{d_str}', 'YYYY-MM-DD'), '{r}', '{c}', {amt});\n")
        
        if i % 500 == 0:
            f.write("  COMMIT;\n")
            
    f.write("  COMMIT;\n")
    f.write("END;\n/\nEXIT;\n")
PYEOF

python3 /tmp/gen_sales.py

# --- Populate Database ---
echo "[3/4] Populating database..."
oracle_query_raw "@ /tmp/sales_data.sql" "hr" > /dev/null 2>&1

# Verify data loaded
COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM sales_transactions;" "hr" | tr -d ' ')
echo "  Loaded $COUNT sales records."

if [ "$COUNT" -lt 2000 ]; then
    echo "ERROR: Failed to load sales data."
    exit 1
fi

# --- Create Reference File ---
echo "[4/4] Creating reference file..."
cat << 'EOF' > /home/ga/Desktop/inefficient_query.sql
-- CURRENT SLOW APPROACH (For Reference Only)
-- This uses 4 separate passes over the data (UNION ALL).
-- Your goal is to replace this with 1 pass using GROUPING SETS.

-- 1. Region and Category
SELECT region, category, SUM(amount) as total
FROM sales_transactions
GROUP BY region, category

UNION ALL

-- 2. Region Subtotals
SELECT region, 'All Categories', SUM(amount)
FROM sales_transactions
GROUP BY region

UNION ALL

-- 3. Category Subtotals
SELECT 'All Regions', category, SUM(amount)
FROM sales_transactions
GROUP BY category

UNION ALL

-- 4. Grand Total
SELECT 'All Regions', 'All Categories', SUM(amount)
FROM sales_transactions;
EOF

chown ga:ga /home/ga/Desktop/inefficient_query.sql
chmod 644 /home/ga/Desktop/inefficient_query.sql

# Remove view if it exists from previous run
oracle_query "DROP VIEW revenue_summary_view;" "hr" > /dev/null 2>&1 || true

# Take initial screenshot
take_screenshot /tmp/task_start_state.png

echo "=== Setup Complete ==="