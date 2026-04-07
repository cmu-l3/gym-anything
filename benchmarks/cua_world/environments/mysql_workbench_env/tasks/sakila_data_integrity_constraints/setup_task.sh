#!/bin/bash
# Setup script for sakila_data_integrity_constraints task

echo "=== Setting up Sakila Data Integrity Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_timestamp

# 2. Ensure MySQL is ready
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# 3. Reset/Clean State
# Drop potential existing objects from previous runs to ensure clean slate
mysql -u root -p'GymAnything#2024' sakila -e "
    ALTER TABLE film DROP CHECK chk_rental_duration;
    ALTER TABLE payment DROP CHECK chk_payment_amount;
    ALTER TABLE film DROP COLUMN price_category;
    DROP FUNCTION IF EXISTS fn_customer_lifetime_value;
" 2>/dev/null || true

# 4. Inject Data Corruption
echo "Injecting data corruption..."

# Corrupt film.rental_duration (10 rows)
# Valid range is typically 3-7 days. We set some to 0 and -1.
mysql -u root -p'GymAnything#2024' sakila -e "
    UPDATE film SET rental_duration = 0 WHERE film_id IN (1, 50, 100, 200, 300, 400, 500, 600);
    UPDATE film SET rental_duration = -1 WHERE film_id IN (700, 800);
" 2>/dev/null

# Corrupt payment.amount (5 rows)
# Set some amounts to negative values
mysql -u root -p'GymAnything#2024' sakila -e "
    UPDATE payment SET amount = -5.99 WHERE payment_id IN (1, 100, 500, 1000, 5000);
" 2>/dev/null

# Verify corruption counts for anti-gaming baseline
BAD_FILMS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM film WHERE rental_duration <= 0")
BAD_PAYMENTS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM payment WHERE amount < 0")

echo "Corruption injected:"
echo "  - Invalid rental_duration count: $BAD_FILMS"
echo "  - Invalid payment amount count: $BAD_PAYMENTS"

echo "$BAD_FILMS" > /tmp/initial_bad_films
echo "$BAD_PAYMENTS" > /tmp/initial_bad_payments

# 5. Prepare Output Directory
mkdir -p /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/data_integrity_report.csv

# 6. Start/Focus MySQL Workbench
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

focus_workbench
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="