#!/bin/bash
# Setup script for sakila_customer_email_recovery task

echo "=== Setting up Sakila Customer Email Recovery Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Ensure MySQL Workbench is running (ready for agent)
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi
focus_workbench

echo "Preparing data scenario..."

# 1. Generate the backup CSV file from the current valid data
# We select Store 2 customers. We intentionally rename columns to simulate a real backup drift.
# Columns: customer_id -> cust_ref_id, email -> contact_email
mysql -u root -p'GymAnything#2024' sakila -B -e "
    SELECT customer_id as cust_ref_id, email as contact_email 
    FROM customer 
    WHERE store_id = 2;
" | sed 's/\t/,/g' > /home/ga/Documents/cust_backup_store2.csv

# Verify backup creation
if [ -s "/home/ga/Documents/cust_backup_store2.csv" ]; then
    echo "Backup CSV created successfully."
    chmod 666 /home/ga/Documents/cust_backup_store2.csv
    chown ga:ga /home/ga/Documents/cust_backup_store2.csv
else
    echo "ERROR: Failed to create backup CSV."
    exit 1
fi

# 2. Record "Ground Truth" for verification (store ID and original email)
# We'll pick 3 specific random IDs to verify later
mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT customer_id, email FROM customer WHERE store_id = 2 ORDER BY RAND() LIMIT 3;
" > /tmp/ground_truth_samples.txt

# 3. Corrupt the database (The Incident)
echo "Simulating data loss incident..."
mysql -u root -p'GymAnything#2024' sakila -e "
    UPDATE customer SET email = NULL WHERE store_id = 2;
"

# 4. Verify Corruption
NULL_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM customer WHERE email IS NULL;")
echo "Corruption complete. Customers with NULL email: $NULL_COUNT"

# 5. Clean up previous exports
rm -f /home/ga/Documents/exports/recovered_emails.csv 2>/dev/null || true

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "The user must now restore the emails."