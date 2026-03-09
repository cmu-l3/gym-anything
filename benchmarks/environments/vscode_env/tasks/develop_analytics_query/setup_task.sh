#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Develop Analytics Query Task ==="

WORKSPACE_DIR="/home/ga/workspace/sales_analysis"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create Python script to generate SQLite database with realistic sales data
cat > "$WORKSPACE_DIR/create_database.py" << 'PYEOF'
import sqlite3
import random
import string
from datetime import datetime, timedelta

conn = sqlite3.connect('sales.db')
cursor = conn.cursor()

# Create tables
cursor.execute('DROP TABLE IF EXISTS sales')
cursor.execute('DROP TABLE IF EXISTS products')
cursor.execute('DROP TABLE IF EXISTS customers')

cursor.execute('''
CREATE TABLE products (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT,
    price REAL NOT NULL
)
''')

cursor.execute('''
CREATE TABLE customers (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT,
    region TEXT
)
''')

cursor.execute('''
CREATE TABLE sales (
    id INTEGER PRIMARY KEY,
    product_id INTEGER,
    customer_id INTEGER,
    region TEXT,
    quantity INTEGER,
    sale_date TEXT,
    FOREIGN KEY (product_id) REFERENCES products(id),
    FOREIGN KEY (customer_id) REFERENCES customers(id)
)
''')

# Seed for reproducibility
random.seed(42)

# Insert products (50 products)
categories = ['Electronics', 'Furniture', 'Clothing', 'Food', 'Books']
product_names = [
    'Widget', 'Gadget', 'Gizmo', 'Device', 'Tool', 'Item', 'Product', 
    'Article', 'Component', 'Unit', 'Piece', 'Element', 'Module', 'Part'
]

for i in range(1, 51):
    base_name = random.choice(product_names)
    suffix = ''.join(random.choices(string.ascii_uppercase, k=2))
    name = f"{base_name} {suffix}{i}"
    category = random.choice(categories)
    price = round(random.uniform(10.0, 500.0), 2)
    cursor.execute(
        "INSERT INTO products VALUES (?, ?, ?, ?)",
        (i, name, category, price)
    )

# Insert customers (100 customers)
regions = ['North', 'South', 'East', 'West']
first_names = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve', 'Frank', 'Grace', 'Henry', 'Ivy', 'Jack']
last_names = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez']

for i in range(1, 101):
    fname = random.choice(first_names)
    lname = random.choice(last_names)
    name = f"{fname} {lname}"
    email = f"{fname.lower()}.{lname.lower()}{i}@example.com"
    region = random.choice(regions)
    cursor.execute(
        "INSERT INTO customers VALUES (?, ?, ?, ?)",
        (i, name, email, region)
    )

# Insert sales for Q4 2024 (Oct, Nov, Dec)
start_date = datetime(2024, 10, 1)
end_date = datetime(2024, 12, 31)
days_diff = (end_date - start_date).days

for i in range(1, 501):
    product_id = random.randint(1, 50)
    customer_id = random.randint(1, 100)
    
    # 90% of sales have region, 10% have NULL (data quality issue)
    if random.random() < 0.9:
        region = random.choice(regions)
    else:
        region = None
    
    quantity = random.randint(1, 10)
    sale_date = start_date + timedelta(days=random.randint(0, days_diff))
    
    cursor.execute(
        "INSERT INTO sales VALUES (?, ?, ?, ?, ?, ?)",
        (i, product_id, customer_id, region, quantity, sale_date.strftime('%Y-%m-%d'))
    )

conn.commit()

# Generate expected output (correct query)
query = """
-- Calculate product revenue by region for Q4 2024
-- Step 1: Join sales with products and aggregate
WITH product_revenue AS (
    SELECT 
        s.region,
        p.name AS product_name,
        SUM(p.price * s.quantity) AS total_revenue,
        COUNT(DISTINCT s.customer_id) AS customer_count
    FROM sales s
    JOIN products p ON s.product_id = p.id
    WHERE s.region IS NOT NULL
      AND s.sale_date >= '2024-10-01'
      AND s.sale_date <= '2024-12-31'
    GROUP BY s.region, p.name
),
-- Step 2: Rank products within each region
ranked_products AS (
    SELECT 
        region,
        product_name,
        total_revenue,
        customer_count,
        RANK() OVER (PARTITION BY region ORDER BY total_revenue DESC) AS rank
    FROM product_revenue
)
-- Step 3: Filter top 5 per region
SELECT 
    region,
    product_name,
    total_revenue,
    customer_count,
    rank
FROM ranked_products
WHERE rank <= 5
ORDER BY region, rank;
"""

import pandas as pd
expected_df = pd.read_sql_query(query, conn)
expected_df.to_csv('expected_output.csv', index=False)

print(f"✓ Database created with {cursor.execute('SELECT COUNT(*) FROM sales').fetchone()[0]} sales records")
print(f"✓ Expected output has {len(expected_df)} rows")

conn.close()
PYEOF

# Run database creation script
cd "$WORKSPACE_DIR"
echo "Creating database with sales data..."
sudo -u ga python3 create_database.py

# Create schema documentation (intentionally incomplete)
cat > "$WORKSPACE_DIR/schema_notes.md" << 'EOF'
# Sales Database Schema Notes

## Overview

This SQLite database contains sales transaction data for Q4 2024.

## Tables

### products
- `id` (INTEGER PRIMARY KEY): Product identifier
- `name` (TEXT): Product name
- `category` (TEXT): Product category
- `price` (REAL): Unit price in dollars

### sales
- `id` (INTEGER PRIMARY KEY): Transaction identifier
- `product_id` (INTEGER): Reference to products table
- `customer_id` (INTEGER): Reference to customers table
- `region` (TEXT): Sales region (North, South, East, West)
- `quantity` (INTEGER): Number of units sold
- `sale_date` (TEXT): Date in YYYY-MM-DD format

**⚠️ WARNING**: Some sales records have NULL region values due to data quality issues from legacy system migration. These should be excluded from analysis.

### customers
- `id` (INTEGER PRIMARY KEY): Customer identifier
- `name` (TEXT): Customer name
- `email` (TEXT): Email address
- `region` (TEXT): Customer's region

## Business Requirements

**Question**: What are the top 5 products by revenue for each region in Q4 2024, including the customer count for each product?

**Q4 2024 Definition**: October 1, 2024 through December 31, 2024 (inclusive)

**Required Metrics**:
- **Total Revenue**: Sum of (price × quantity) for each product-region combination
- **Customer Count**: Number of unique customers who purchased each product in each region

**Expected Output Columns**:
1. `region` - The sales region name
2. `product_name` - The product name
3. `total_revenue` - Total revenue for this product in this region
4. `customer_count` - Count of unique customers
5. `rank` - Rank of product within region (1-5)

**Requirements**:
- Only include sales with non-NULL regions
- Only include sales from Q4 2024 date range
- Rank products by total_revenue (highest first) within each region
- Include only top 5 products per region
- Order results by region (alphabetically), then by rank

## Hints

- You'll need to JOIN the `sales` and `products` tables
- Use aggregate functions: `SUM()`, `COUNT(DISTINCT ...)`
- Use window function: `RANK() OVER (PARTITION BY ... ORDER BY ...)`
- Use CTEs (WITH clause) for readability
- Filter dates using: `sale_date >= '2024-10-01' AND sale_date <= '2024-12-31'`
- Filter NULL regions using: `region IS NOT NULL`
- Group by region and product name for aggregation

## File Location

Save your query to: `/home/ga/workspace/sales_analysis/query_solution.sql`

The query should be well-documented with SQL comments explaining the logic.
EOF

# Clean up temporary Python script
rm -f "$WORKSPACE_DIR/create_database.py"

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/schema_notes.md'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Develop Analytics Query Task Setup Complete ==="
echo ""
echo "📊 Task Context:"
echo "   You are a data analyst working on Q4 2024 sales report"
echo ""
echo "📝 Your Task:"
echo "   Write a SQL query to find the top 5 products by revenue"
echo "   for each region in Q4 2024, including customer counts"
echo ""
echo "📁 Workspace Files:"
echo "   - sales.db: SQLite database with sales data"
echo "   - schema_notes.md: Database documentation (OPEN THIS FIRST)"
echo "   - expected_output.csv: Sample expected results"
echo ""
echo "💾 Save your query to:"
echo "   /home/ga/workspace/sales_analysis/query_solution.sql"
echo ""
echo "✅ Requirements:"
echo "   - Use JOINs to combine tables"
echo "   - Calculate revenue as price × quantity"
echo "   - Count distinct customers per product-region"
echo "   - Use RANK() window function for ranking"
echo "   - Filter Q4 2024 dates (2024-10-01 to 2024-12-31)"
echo "   - Exclude NULL regions"
echo "   - Add SQL comments to document logic"