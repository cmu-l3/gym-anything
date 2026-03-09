#!/bin/bash
set -e
echo "=== Setting up convert_db_storage_engine task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Ensure Virtualmin is ready and logged in
# ---------------------------------------------------------------
ensure_virtualmin_ready

# ---------------------------------------------------------------
# 2. Create the Virtual Server (if not exists)
# ---------------------------------------------------------------
DOMAIN="legacy-systems.test"
DB_NAME="inventory_db"
DB_PASS="InventoryPass123!"

if ! virtualmin_domain_exists "$DOMAIN"; then
    echo "Creating virtual server $DOMAIN..."
    # Create domain with MySQL enabled
    virtualmin create-domain \
        --domain "$DOMAIN" \
        --pass "$DB_PASS" \
        --desc "Legacy Systems Inc." \
        --unix --dir --webmin --web --dns --mysql \
        --default-features \
        2>&1 | tail -5
    sleep 5
fi

# ---------------------------------------------------------------
# 3. Setup Database and Table
# ---------------------------------------------------------------
echo "Setting up database $DB_NAME..."

# Create specific database if it doesn't exist (Virtualmin might have created one named 'legacy-systems')
if ! mysql_database_exists "$DB_NAME"; then
    virtualmin create-database --domain "$DOMAIN" --name "$DB_NAME" --type mysql
fi

# Reset the table to MyISAM to ensure starting state
echo "Resetting 'products' table to MyISAM..."
virtualmin_db_query "DROP TABLE IF EXISTS ${DB_NAME}.products;"

# Create Table with MyISAM Engine
virtualmin_db_query "CREATE TABLE ${DB_NAME}.products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sku VARCHAR(20) NOT NULL,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50),
    price DECIMAL(10,2),
    stock_qty INT,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=MyISAM;"

# ---------------------------------------------------------------
# 4. Populate with Realistic Data
# ---------------------------------------------------------------
echo "Populating data..."

# Generate SQL insert file using python for realistic data
cat << 'EOF' > /tmp/gen_data.py
import random

tools = ['Hammer', 'Screwdriver', 'Wrench', 'Drill', 'Saw', 'Pliers', 'Level', 'Tape Measure', 'Chisel', 'Sander']
brands = ['ProBuild', 'MegaFix', 'ToughTool', 'HomeMate', 'BuildRight']
cats = ['Hand Tools', 'Power Tools', 'Accessories']

print("INSERT INTO products (sku, name, category, price, stock_qty) VALUES")
rows = []
for i in range(50):
    tool = random.choice(tools)
    brand = random.choice(brands)
    cat = 'Power Tools' if tool in ['Drill', 'Saw', 'Sander'] else 'Hand Tools'
    sku = f"{brand[:3].upper()}-{tool[:3].upper()}-{random.randint(1000,9999)}"
    name = f"{brand} {tool} {random.choice(['Pro', 'Basic', 'X-Series'])}"
    price = round(random.uniform(5.99, 150.00), 2)
    stock = random.randint(0, 500)
    rows.append(f"('{sku}', '{name}', '{cat}', {price}, {stock})")

print(",\n".join(rows) + ";")
EOF

python3 /tmp/gen_data.py > /tmp/insert_data.sql

# Execute Insert
mysql -u root -pGymAnything123! "$DB_NAME" < /tmp/insert_data.sql 2>/dev/null

# ---------------------------------------------------------------
# 5. Record Initial State for Verification
# ---------------------------------------------------------------
# Get row count
ROW_COUNT=$(virtualmin_db_query "SELECT COUNT(*) FROM ${DB_NAME}.products;" | tail -1)
echo "$ROW_COUNT" > /home/ga/initial_row_count.txt

# Calculate a simple checksum of the data (sum of lengths of names + sum of stock) to verify data integrity later
# We avoid TABLE CHECKSUM as it varies by engine
DATA_HASH=$(virtualmin_db_query "SELECT SUM(LENGTH(name)) + SUM(stock_qty) FROM ${DB_NAME}.products;" | tail -1)
echo "$DATA_HASH" > /home/ga/initial_data_hash.txt

# Verify Engine is MyISAM
ENGINE=$(virtualmin_db_query "SELECT ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_NAME='products';" | tail -1)

echo "Initial Setup Complete:"
echo "  Rows: $ROW_COUNT"
echo "  Engine: $ENGINE"
echo "  Data Hash: $DATA_HASH"

# Navigate to the database list in Firefox to save the agent a step
# We need the domain ID for the URL
DOM_ID=$(get_domain_id "$DOMAIN")
navigate_to "${VIRTUALMIN_URL}/virtual-server/list_databases.cgi?dom=${DOM_ID}"

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="