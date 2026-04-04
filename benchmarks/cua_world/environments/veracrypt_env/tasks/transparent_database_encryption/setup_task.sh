#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Transparent Database Encryption Task ==="

# 1. Clean up previous artifacts
echo "Cleaning previous state..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
rm -f /home/ga/Volumes/crm_encrypted.hc 2>/dev/null || true
rm -rf /home/ga/LegacyCRM 2>/dev/null || true
mkdir -p /home/ga/LegacyCRM/data
mkdir -p /home/ga/MountPoints/secure_store

# 2. Generate Realistic SQLite Data
echo "Generating legacy database..."
DB_PATH="/home/ga/LegacyCRM/data/customers.db"

# We use python to generate a valid SQLite DB with fake data
python3 -c "
import sqlite3
import random
import uuid
import os

db_path = '$DB_PATH'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Create table
c.execute('''CREATE TABLE customers
             (id INTEGER PRIMARY KEY, 
              name TEXT, 
              email TEXT, 
              phone TEXT, 
              account_balance REAL,
              signup_date DATE)''')

# Generate 100 fake records
first_names = ['James', 'Mary', 'John', 'Patricia', 'Robert', 'Jennifer', 'Michael', 'Linda', 'William', 'Elizabeth']
last_names = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez']
domains = ['example.com', 'test.org', 'corp.net', 'mail_provider.com']

data = []
for i in range(100):
    fname = random.choice(first_names)
    lname = random.choice(last_names)
    name = f'{fname} {lname}'
    email = f'{fname.lower()}.{lname.lower()}_{i}@' + random.choice(domains)
    phone = f'555-{random.randint(100,999)}-{random.randint(1000,9999)}'
    balance = round(random.uniform(0, 10000), 2)
    date = f'202{random.randint(0,3)}-{random.randint(1,12):02d}-{random.randint(1,28):02d}'
    data.append((i+1, name, email, phone, balance, date))

c.executemany('INSERT INTO customers VALUES (?,?,?,?,?,?)', data)
conn.commit()
print(f'Created database at {db_path} with {len(data)} records')

# Verify count
c.execute('SELECT COUNT(*) FROM customers')
count = c.fetchone()[0]
with open('/tmp/initial_record_count.txt', 'w') as f:
    f.write(str(count))
conn.close()
"

# 3. Set ownership
chown -R ga:ga /home/ga/LegacyCRM
chown -R ga:ga /home/ga/MountPoints

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Ensure VeraCrypt is running and window is ready
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

# Try to find and focus window, but don't fail if not found (agent might need to start it)
wait_for_window "VeraCrypt" 10 || echo "VeraCrypt window not detected yet"
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 6. Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Legacy Database created at: $DB_PATH"
echo "Target Mount Point created at: /home/ga/MountPoints/secure_store"