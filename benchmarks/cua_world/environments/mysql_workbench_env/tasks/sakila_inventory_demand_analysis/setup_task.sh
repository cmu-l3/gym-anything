#!/bin/bash
# Setup script for sakila_inventory_demand_analysis

echo "=== Setting up Sakila Inventory Demand Analysis Task ==="

source /workspace/scripts/task_utils.sh

# 1. Start MySQL if needed
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# 2. Reset Sakila database to a clean state
echo "Resetting Sakila database..."
# (Assuming standard setup script puts sakila SQLs in /home/ga/Documents/sql_scripts or similar)
# For robustness, we'll rely on the env's pre-loaded state but clean specific tables if needed.
# Just ensuring it's accessible.
mysql -u root -p'GymAnything#2024' -e "USE sakila;" 2>/dev/null || {
    echo "Sakila not found, attempting to reload..."
    # Fallback reload logic if needed, but env should have it.
}

# 3. Inject "Glitch" Data and Specific Test Cases
echo "Injecting data anomalies for July 2005..."

# Ensure we have a clean slate for the 'rental' table modifications from previous runs
# (In a real scenario we might restore from backup, here we just inject)

mysql -u root -p'GymAnything#2024' sakila -e "
    -- 1. Create a 'glitch' record: Return before Rental (Negative Duration)
    -- We'll pick a specific rental_id to modify or insert new ones.
    -- Let's insert a new rental for inventory_id 1 (Academy Dinosaur)
    INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id)
    VALUES ('2005-07-10 10:00:00', 1, 1, '2005-07-10 09:00:00', 1);

    -- 2. Create an 'open' record: NULL return_date in July 2005
    INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id)
    VALUES ('2005-07-20 12:00:00', 2, 1, NULL, 1);
    
    -- 3. Ensure 'secure_file_priv' is set to a path accessible or empty to allow SELECT INTO OUTFILE if agent chooses SQL export
    -- (Cannot easily change my.cnf and restart in this script without privilges/restart, 
    --  but we expect agent to use Workbench GUI export usually. 
    --  If they use SQL export, they usually output to /var/lib/mysql-files. 
    --  We'll skip config changes to minimize disruption.)
" 2>/dev/null

# 4. Clean up previous artifacts
rm -f /home/ga/Documents/exports/high_utilization_films.csv 2>/dev/null
mysql -u root -p'GymAnything#2024' sakila -e "DROP VIEW IF EXISTS v_july_2005_utilization;" 2>/dev/null

# 5. Start Workbench
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

focus_workbench

# 6. Record timestamps and screenshot
date +%s > /tmp/task_start_timestamp
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="