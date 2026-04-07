#!/bin/bash
# Setup script for sakila_business_rules_engine task

echo "=== Setting up Sakila Business Rules Engine Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Ensure Sakila database is present (standard env setup, but verifying)
if ! mysql -u root -p'GymAnything#2024' -e "USE sakila;" 2>/dev/null; then
    echo "ERROR: Sakila database not found. Re-running setup..."
    /workspace/scripts/setup_mysql_workbench.sh
fi

# Clean up previous run artifacts (to ensure agent actually creates them)
echo "Cleaning up previous objects..."
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP TABLE IF EXISTS customer_billing_report;
    DROP VIEW IF EXISTS v_customer_billing_summary;
    DROP FUNCTION IF EXISTS fn_rental_late_days;
    DROP FUNCTION IF EXISTS fn_late_fee;
    DROP FUNCTION IF EXISTS fn_customer_tier;
    DROP FUNCTION IF EXISTS fn_film_popularity;
" 2>/dev/null || true

# Remove previous export file
rm -f /home/ga/Documents/exports/customer_billing_report.csv 2>/dev/null || true

# Ensure MySQL Workbench is running for the agent
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

# Focus the Workbench window
focus_workbench

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

# Record active customer count for verification baseline
ACTIVE_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM customer WHERE active = 1")
echo "$ACTIVE_COUNT" > /tmp/expected_active_count

echo "=== Task setup complete ==="
echo "Clean state established. Sakila database ready."