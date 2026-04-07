#!/bin/bash
# Setup script for sakila_inventory_lifecycle_management task

echo "=== Setting up Sakila Inventory Lifecycle Task ==="

source /workspace/scripts/task_utils.sh

# Define cleanup function to handle existing state
cleanup_db_state() {
    echo "Cleaning up database state..."
    mysql -u root -p'GymAnything#2024' sakila -e "
        DROP TRIGGER IF EXISTS trg_prevent_renting_unavailable;
        DROP PROCEDURE IF EXISTS sp_set_inventory_status;
        ALTER TABLE inventory DROP COLUMN status;
    " 2>/dev/null || true
}

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Reset Sakila to known state
cleanup_db_state

# Ensure Item 1 is currently rented (for testing the stored procedure logic later)
# We set return_date to NULL for the last rental of inventory_id 1
echo "Ensuring test data constraints..."
mysql -u root -p'GymAnything#2024' sakila -e "
    UPDATE rental SET return_date = NULL 
    WHERE inventory_id = 1 
    ORDER BY rental_date DESC LIMIT 1;
" 2>/dev/null

# Clean previous export
rm -f /home/ga/Documents/exports/unavailable_inventory.csv 2>/dev/null || true

# Ensure MySQL Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

# Focus Workbench
focus_workbench

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "State prepared: Inventory table clean (no status column). Item 1 is currently rented."