#!/bin/bash
set -e
echo "=== Setting up Messy CSV Normalization Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Documents/imports
mkdir -p /home/ga/Documents/scripts
chown -R ga:ga /home/ga/Documents

# Path for the database
DB_PATH="/home/ga/Documents/databases/chinook.db"

# verify DB exists (setup_dbeaver.sh should have created it, but good to be sure)
if [ ! -f "$DB_PATH" ]; then
    echo "Chinook DB not found, copying..."
    cp /workspace/data/chinook.db "$DB_PATH" || \
    wget -q -O "$DB_PATH" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
fi

# Generate the messy CSV
# We select real data from Chinook, then use Python to "mess it up"
echo "Generating messy CSV data..."
sqlite3 -header -csv "$DB_PATH" "SELECT InvoiceId, InvoiceDate, CustomerId, Total FROM invoices LIMIT 50;" > /tmp/base_data.csv

python3 -c "
import csv
import random
from datetime import datetime

input_file = '/tmp/base_data.csv'
output_file = '/home/ga/Documents/imports/legacy_sales_dump.csv'

# Fetch customer names to embed
# For simplicity in this script, we'll just use a generic name pattern since the task 
# asks to extract the ID, not match the name perfectly to the Customers table.
def get_dummy_name(id):
    return f'Customer_{id}'

with open(input_file, 'r') as f_in, open(output_file, 'w', newline='') as f_out:
    reader = csv.DictReader(f_in)
    writer = csv.writer(f_out)
    
    # Write Header
    writer.writerow(['TrxID', 'TrxDate', 'CustomerDetail', 'Amount'])
    
    total_amount = 0.0
    
    for row in reader:
        # 1. TrxID -> SaleId (keep as is)
        trx_id = row['InvoiceId']
        
        # 2. InvoiceDate (YYYY-MM-DD HH:MM:SS) -> DD/MM/YYYY
        # SQLite often stores dates as strings. Chinook usually uses 'YYYY-MM-DD 00:00:00'
        raw_date = row['InvoiceDate'].split(' ')[0] 
        try:
            dt_obj = datetime.strptime(raw_date, '%Y-%m-%d')
            formatted_date = dt_obj.strftime('%d/%m/%Y')
        except:
            formatted_date = '01/01/2000' # Fallback
            
        # 3. CustomerId -> 'Name [ID:123]'
        cust_id = row['CustomerId']
        cust_str = f'Valued Customer [ID:{cust_id}]'
        
        # 4. Total -> '$ 1,234.56'
        try:
            amount = float(row['Total'])
            total_amount += amount
            # Add some randomness to formatting for realism? 
            # No, keep consistency for the regex challenge.
            formatted_amount = f'$ {amount:,.2f}'
        except:
            formatted_amount = '$ 0.00'
            
        writer.writerow([trx_id, formatted_date, cust_str, formatted_amount])

    # Save expected sum for verification
    with open('/tmp/expected_sum.txt', 'w') as f_sum:
        f_sum.write(str(total_amount))
"

chown ga:ga /home/ga/Documents/imports/legacy_sales_dump.csv

# Ensure DBeaver is running
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 15
fi

# Focus DBeaver
focus_dbeaver
maximize_window "DBeaver"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="