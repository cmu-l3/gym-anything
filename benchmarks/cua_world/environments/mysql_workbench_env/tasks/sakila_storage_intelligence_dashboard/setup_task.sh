#!/bin/bash
# Setup script for Sakila Storage Intelligence Dashboard task

echo "=== Setting up Storage Intelligence Dashboard Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Reset Sakila State & Clean up views
echo "Cleaning up previous state..."
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP VIEW IF EXISTS v_maintenance_required;
    DROP VIEW IF EXISTS v_storage_metrics;
" 2>/dev/null || true

# Remove previous export
rm -f /home/ga/Documents/exports/maintenance_report.csv 2>/dev/null || true
mkdir -p /home/ga/Documents/exports

# --- SIMULATE DATA FRAGMENTATION ---
# To make the task realistic, we need actual "data_free" (fragmentation) in tables.
# We will massively delete rows from 'payment' and 'rental' to create holes in the InnoDB pages.

echo "Simulating table fragmentation..."
mysql -u root -p'GymAnything#2024' sakila -e "
    -- Create fragmentation in payment table (~16k rows)
    DELETE FROM payment WHERE payment_id % 2 = 0; 
    DELETE FROM payment WHERE payment_id % 3 = 0;
    
    -- Create fragmentation in rental table (~16k rows)
    DELETE FROM rental WHERE rental_id % 2 = 0;
    DELETE FROM rental WHERE rental_id % 3 = 0;
    
    -- Analyze tables to update statistics in information_schema
    ANALYZE TABLE payment;
    ANALYZE TABLE rental;
" 2>/dev/null

# Verify fragmentation exists (debug info)
echo "Verifying fragmentation state:"
mysql -u root -p'GymAnything#2024' -e "
    SELECT table_name, data_length, data_free, 
    (data_free/data_length)*100 as frag_pct 
    FROM information_schema.tables 
    WHERE table_schema='sakila' AND table_name IN ('payment', 'rental');
"

# Ensure MySQL Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

# Focus the Workbench window
focus_workbench

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "The system is ready. 'payment' and 'rental' tables are now fragmented."