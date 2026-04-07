#!/bin/bash
echo "=== Setting up E-Commerce RFM Segmentation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Create expected export directory
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports
chmod 777 /home/ga/Documents/exports

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

# Drop and recreate the RETAIL_BI schema cleanly
echo "Setting up RETAIL_BI schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER retail_bi CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER retail_bi IDENTIFIED BY RetailBI2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE TABLE, CREATE SESSION TO retail_bi;
EXIT;" "system"

echo "RETAIL_BI user created."

# Create the target table
sudo docker exec -i oracle-xe sqlplus -s retail_bi/RetailBI2024@//localhost:1521/XEPDB1 << 'EOSQL'
CREATE TABLE online_retail (
    InvoiceNo VARCHAR2(20),
    StockCode VARCHAR2(20),
    Description VARCHAR2(200),
    Quantity NUMBER,
    InvoiceDate DATE,
    UnitPrice NUMBER(10,2),
    CustomerID NUMBER,
    Country VARCHAR2(100)
);
EXIT;
EOSQL

echo "Generating and loading realistic synthetic E-Commerce data (offline mode)..."

# Generate 3000 realistic records reflecting e-commerce noise (cancellations, nulls, negative values)
python3 << 'EOF'
import random
from datetime import datetime, timedelta

def generate_sql():
    num_records = 3000
    start_date = datetime(2010, 12, 1)
    
    # 500 distinct customers
    customers = [random.randint(12000, 18000) for _ in range(500)]
    
    # Sample products
    products = [
        ("85123A", "WHITE HANGING HEART T-LIGHT HOLDER", 2.55),
        ("71053", "WHITE METAL LANTERN", 3.39),
        ("84406B", "CREAM CUPID HEARTS COAT HANGER", 2.75),
        ("84029G", "KNITTED UNION FLAG HOT WATER BOTTLE", 3.39),
        ("84029E", "RED WOOLLY HOTTIE WHITE HEART", 3.39),
        ("22752", "SET 7 BABUSHKA NESTING BOXES", 7.65),
        ("21730", "GLASS STAR FROSTED T-LIGHT HOLDER", 4.25),
        ("22632", "HAND WARMER RECORD DESIGN", 1.85),
        ("22633", "HAND WARMER UNION JACK", 1.85),
        ("22866", "HAND WARMER SCOTTY DOG DESIGN", 2.10)
    ]
    
    with open('/tmp/insert_retail.sql', 'w') as f:
        f.write("SET DEFINE OFF;\n")
        
        batch = []
        for i in range(num_records):
            prod = random.choice(products)
            # 10% chance of missing CustomerID
            cust = random.choice(customers) if random.random() > 0.10 else "NULL"
            
            # 5% cancellations (Starts with C, negative quantity)
            is_cancel = random.random() < 0.05
            inv = f"C5{random.randint(10000, 99999)}" if is_cancel else f"5{random.randint(10000, 99999)}"
            
            qty = random.randint(1, 20)
            if is_cancel or random.random() < 0.02:
                qty = -qty
                
            # 5% chance of zero/negative pricing anomalies
            unit_price = prod[2] if random.random() > 0.05 else 0.0
            
            dt = start_date + timedelta(days=random.randint(0, 365), hours=random.randint(0, 23), minutes=random.randint(0, 59))
            dt_str = dt.strftime('%Y-%m-%d %H:%M:%S')
            
            val = f"('{inv}', '{prod[0]}', '{prod[1]}', {qty}, TO_DATE('{dt_str}', 'YYYY-MM-DD HH24:MI:SS'), {unit_price}, {cust}, 'United Kingdom')"
            batch.append(val)
            
            if len(batch) >= 100 or i == num_records - 1:
                f.write("INSERT ALL\n")
                for b in batch:
                    f.write(f"  INTO online_retail VALUES {b}\n")
                f.write("SELECT 1 FROM DUAL;\n")
                batch = []
                
        f.write("COMMIT;\nEXIT;\n")

generate_sql()
EOF

# Load the generated SQL into Oracle
sudo docker exec -i oracle-xe sqlplus -s retail_bi/RetailBI2024@//localhost:1521/XEPDB1 < /tmp/insert_retail.sql > /dev/null
echo "Data loaded successfully."

# Maximize and focus SQL Developer if running
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial state screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="