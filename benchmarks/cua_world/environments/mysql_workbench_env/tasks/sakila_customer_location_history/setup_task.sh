#!/bin/bash
# Setup script for sakila_customer_location_history task

echo "=== Setting up Sakila Customer Location History Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Reset Sakila State (Clean up previous runs)
echo "Resetting database state..."
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP TRIGGER IF EXISTS trg_track_address_changes;
    DROP TABLE IF EXISTS customer_address_history;
    
    -- Reset Mary Smith (ID 1) to original address (ID 5)
    UPDATE customer SET address_id = 5 WHERE customer_id = 1;
" 2>/dev/null || true

# Clean up export file
rm -f /home/ga/Documents/exports/mary_smith_history.csv 2>/dev/null || true

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

# Initial count of customers for verification reference
CUSTOMER_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM customer")
echo "$CUSTOMER_COUNT" > /tmp/initial_customer_count

echo "=== Task setup complete ==="
echo "State reset: Trigger dropped, history table dropped, Mary Smith at address 5."