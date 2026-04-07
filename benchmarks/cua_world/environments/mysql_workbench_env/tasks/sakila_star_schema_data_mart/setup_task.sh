#!/bin/bash
# Setup script for sakila_star_schema_data_mart task

echo "=== Setting up Sakila Star Schema Data Mart Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Ensure MySQL Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

# Focus the Workbench window
focus_workbench

# Clean up previous attempts: Drop sakila_mart if it exists
echo "Cleaning up previous database state..."
mysql -u root -p'GymAnything#2024' -e "DROP DATABASE IF EXISTS sakila_mart;" 2>/dev/null

# Clean up previous export file
echo "Cleaning up previous export files..."
rm -f /home/ga/Documents/exports/monthly_store_performance.csv 2>/dev/null

# Ensure Sakila is present (reloading is expensive, so just check existence)
if ! mysql -u root -p'GymAnything#2024' -e "USE sakila;" 2>/dev/null; then
    echo "Sakila database missing! Reloading..."
    # The environment setup script usually handles this, but valid fallback:
    if [ -f /tmp/sakila-db/sakila-schema.sql ]; then
        mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-schema.sql
        mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-data.sql
    fi
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="