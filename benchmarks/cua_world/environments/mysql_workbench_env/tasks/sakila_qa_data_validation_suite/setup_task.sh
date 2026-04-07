#!/bin/bash
# Setup script for sakila_qa_data_validation_suite task

echo "=== Setting up Sakila QA Data Validation Suite Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils not available
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type start_workbench &>/dev/null; then
    start_workbench() { su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"; sleep 10; }
fi
if ! type focus_workbench &>/dev/null; then
    focus_workbench() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "workbench\|mysql" | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true; }
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# 1. Clean up previous run artifacts
echo "Cleaning up previous runs..."
rm -f /home/ga/Documents/exports/qa_test_results.csv 2>/dev/null || true
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP TABLE IF EXISTS qa_test_results;
    DROP PROCEDURE IF EXISTS sp_run_qa_suite;
" 2>/dev/null || true

# 2. Reset data to clean state (reload Sakila data tables if needed, but for now we just fix what we might have broken)
# We assume Sakila is loaded. We'll run updates to ensure "clean" state before planting bugs, 
# just in case the task runs multiple times without full reset.
echo "Resetting data to known good state..."
mysql -u root -p'GymAnything#2024' sakila -e "
    UPDATE rental SET return_date = DATE_ADD(rental_date, INTERVAL 1 DAY) WHERE return_date < rental_date;
    UPDATE payment SET amount = ABS(amount);
    UPDATE customer SET email = CONCAT(email, '@example.com') WHERE email NOT LIKE '%@%';
    UPDATE film SET rental_duration = 3 WHERE rental_duration = 0;
    UPDATE film SET replacement_cost = 19.99 WHERE replacement_cost = 0.00;
" 2>/dev/null || true

# 3. Plant Data Quality Issues
echo "Planting data quality issues..."

# Issue 1: Temporal violations (return_date < rental_date) - 5 records
# Using specific rental_ids to be deterministic
mysql -u root -p'GymAnything#2024' sakila -e "
    UPDATE rental 
    SET return_date = DATE_SUB(rental_date, INTERVAL 5 DAY) 
    WHERE rental_id IN (1, 10, 20, 30, 40);
" 2>/dev/null

# Issue 2: Negative payments - 4 records
mysql -u root -p'GymAnything#2024' sakila -e "
    UPDATE payment 
    SET amount = -1.99 
    WHERE payment_id IN (1, 2, 3, 4);
" 2>/dev/null

# Issue 3: Invalid emails (missing @) - 3 records
mysql -u root -p'GymAnything#2024' sakila -e "
    UPDATE customer 
    SET email = REPLACE(email, '@', '.') 
    WHERE customer_id IN (1, 2, 3);
" 2>/dev/null

# Issue 4: Zero rental duration - 3 records
mysql -u root -p'GymAnything#2024' sakila -e "
    UPDATE film 
    SET rental_duration = 0 
    WHERE film_id IN (1, 2, 3);
" 2>/dev/null

# Issue 5: Zero replacement cost - 2 records
mysql -u root -p'GymAnything#2024' sakila -e "
    UPDATE film 
    SET replacement_cost = 0.00 
    WHERE film_id IN (10, 11);
" 2>/dev/null

# Record initial counts to file for verification logic
echo "5" > /tmp/expected_temporal_violations
echo "4" > /tmp/expected_negative_payments
echo "3" > /tmp/expected_invalid_emails
echo "3" > /tmp/expected_zero_duration
echo "2" > /tmp/expected_zero_cost

# Ensure exports directory exists
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

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

echo "=== Task Setup Complete ==="
echo "Data issues planted. Ready for agent."