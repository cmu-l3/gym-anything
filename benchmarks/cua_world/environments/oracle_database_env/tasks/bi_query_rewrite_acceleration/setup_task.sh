#!/bin/bash
# Setup for bi_query_rewrite_acceleration
# Creates SH_LITE schema, generates synthetic retail data, and plants the slow query.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up BI Query Rewrite Task ==="

# 1. Wait for Oracle
echo "Waiting for Oracle..."
# Simple check using system user
for i in {1..30}; do
    if sudo docker exec oracle-xe sqlplus -s system/OraclePassword123@localhost:1521/XEPDB1 <<< "SELECT 1 FROM dual;" | grep -q "1"; then
        echo "Oracle is ready."
        break
    fi
    sleep 2
done

# 2. Python script to generate data SQL
# We generate SQL file to load via sqlplus for speed
echo "Generating synthetic data..."
cat << 'EOF' > /tmp/gen_data.py
import random

# Constants
NUM_PRODUCTS = 50
NUM_CUSTOMERS = 100
NUM_SALES = 50000

categories = ['Electronics', 'Clothing', 'Home', 'Books', 'Toys']
countries = ['US', 'GB', 'DE', 'FR', 'JP', 'CA', 'AU']

# Generate Products
with open('/tmp/load_data.sql', 'w') as f:
    f.write("SET DEFINE OFF;\n")
    f.write("INSERT INTO products (prod_id, prod_name, prod_category, prod_price) VALUES (1, 'Unknown', 'Misc', 0);\n") # Dummy
    for i in range(1, NUM_PRODUCTS + 1):
        cat = random.choice(categories)
        price = round(random.uniform(10.0, 500.0), 2)
        f.write(f"INSERT INTO products (prod_id, prod_name, prod_category, prod_price) VALUES ({i+1}, 'Product_{i}', '{cat}', {price});\n")
    
    # Generate Customers
    for i in range(1, NUM_CUSTOMERS + 1):
        country = random.choice(countries)
        f.write(f"INSERT INTO customers (cust_id, cust_first_name, cust_last_name, country_iso_code) VALUES ({i}, 'Cust_{i}', 'Name_{i}', '{country}');\n")
    
    f.write("COMMIT;\n")

    # Generate Sales (Bulk insert block for speed)
    f.write("BEGIN\n")
    for i in range(NUM_SALES):
        p_id = random.randint(2, NUM_PRODUCTS + 1)
        c_id = random.randint(1, NUM_CUSTOMERS)
        # Add some seasonality/logic
        amt = round(random.uniform(10.0, 1000.0), 2)
        # Oracle date format: DD-MON-YY
        day = random.randint(1, 28)
        month = random.choice(['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'])
        year = random.choice(['23', '24'])
        
        f.write(f"  INSERT INTO sales (sale_id, prod_id, cust_id, amount_sold, time_id) VALUES ({i}, {p_id}, {c_id}, {amt}, '{day}-{month}-{year}');\n")
        
        if i % 1000 == 0:
            f.write("  COMMIT;\n")
    f.write("  COMMIT;\n")
    f.write("END;\n/\n")
EOF

python3 /tmp/gen_data.py

# 3. Setup Schema and Tables
echo "Creating schema and loading data..."
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@localhost:1521/XEPDB1 << 'SQL_SETUP'
-- Cleanup
DROP USER sh_lite CASCADE;

-- Create User
CREATE USER sh_lite IDENTIFIED BY password123;
GRANT CONNECT, RESOURCE TO sh_lite;
GRANT CREATE MATERIALIZED VIEW TO sh_lite;
GRANT QUERY REWRITE TO sh_lite;
GRANT CREATE TABLE TO sh_lite;
GRANT UNLIMITED TABLESPACE TO sh_lite;

-- Create Tables
CONNECT sh_lite/password123@localhost:1521/XEPDB1;

CREATE TABLE products (
    prod_id NUMBER PRIMARY KEY,
    prod_name VARCHAR2(100),
    prod_category VARCHAR2(50),
    prod_price NUMBER(10,2)
);

CREATE TABLE customers (
    cust_id NUMBER PRIMARY KEY,
    cust_first_name VARCHAR2(50),
    cust_last_name VARCHAR2(50),
    country_iso_code VARCHAR2(2)
);

CREATE TABLE sales (
    sale_id NUMBER PRIMARY KEY,
    prod_id NUMBER NOT NULL,
    cust_id NUMBER NOT NULL,
    amount_sold NUMBER(10,2),
    time_id DATE,
    CONSTRAINT fk_prod FOREIGN KEY (prod_id) REFERENCES products(prod_id),
    CONSTRAINT fk_cust FOREIGN KEY (cust_id) REFERENCES customers(cust_id)
);

-- Load Data
@/tmp/load_data.sql

-- Gather Stats (Critical for CBO to choose Rewrite)
EXEC DBMS_STATS.GATHER_TABLE_STATS('SH_LITE', 'SALES');
EXEC DBMS_STATS.GATHER_TABLE_STATS('SH_LITE', 'PRODUCTS');
EXEC DBMS_STATS.GATHER_TABLE_STATS('SH_LITE', 'CUSTOMERS');

EXIT;
SQL_SETUP

# 4. Plant the Query File
echo "Planting dashboard query..."
cat << 'QRY' > /home/ga/Desktop/dashboard_query.sql
/* 
   DASHBOARD REPORT: GLOBAL SALES SUMMARY
   ISSUE: Query takes too long to execute on full dataset.
   REQUIREMENT: Optimize using Materialized View Query Rewrite.
   DO NOT MODIFY THIS QUERY TEXT IN THE APPLICATION.
*/

SELECT 
    p.prod_category,
    c.country_iso_code,
    SUM(s.amount_sold) as total_sales,
    COUNT(*) as num_txns
FROM 
    sales s
    JOIN products p ON s.prod_id = p.prod_id
    JOIN customers c ON s.cust_id = c.cust_id
GROUP BY 
    p.prod_category, 
    c.country_iso_code
ORDER BY 
    total_sales DESC;
QRY

# Set ownership
chown ga:ga /home/ga/Desktop/dashboard_query.sql

# 5. Timestamp and Initial Screenshot
date +%s > /tmp/task_start_time.txt

# Launch DBeaver or Terminal to give hint of tools
# (Optional, but helps agent get started)
# We won't auto-launch DBeaver to save resources, but ensure environment is clean.

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="