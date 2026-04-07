#!/bin/bash
# Setup script for sakila_revenue_correction_audit task

echo "=== Setting up Sakila Revenue Correction Audit Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Ensure Workbench is running (so agent sees it immediately)
if [ "$(is_workbench_running)" = "false" ]; then
    start_workbench
    sleep 5
fi
focus_workbench

# Clean previous artifacts
rm -f /home/ga/Documents/exports/underpayment_audit.csv 2>/dev/null
mysql -u root -p'GymAnything#2024' sakila -e "DROP VIEW IF EXISTS v_audit_underpayments;" 2>/dev/null

echo "Injecting data corruption (Simulating POS Glitch)..."

# 1. Select ~40 payments for films that cost > 0.99 (so 0.01 is definitely wrong)
# We store these IDs and their correct rates to ground truth
mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT p.payment_id, f.rental_rate 
    FROM payment p
    JOIN rental r ON p.rental_id = r.rental_id
    JOIN inventory i ON r.inventory_id = i.inventory_id
    JOIN film f ON i.film_id = f.film_id
    WHERE f.rental_rate > 2.99
    LIMIT 40;
" > /tmp/ground_truth_targets.txt

# 2. Corrupt these payments to 0.01
# We use a temporary table approach to update them efficiently in SQL
mysql -u root -p'GymAnything#2024' sakila -e "
    CREATE TEMPORARY TABLE corruption_targets (
        payment_id SMALLINT UNSIGNED PRIMARY KEY
    );
    
    INSERT INTO corruption_targets (payment_id)
    SELECT p.payment_id
    FROM payment p
    JOIN rental r ON p.rental_id = r.rental_id
    JOIN inventory i ON r.inventory_id = i.inventory_id
    JOIN film f ON i.film_id = f.film_id
    WHERE f.rental_rate > 2.99
    LIMIT 40;

    UPDATE payment p
    JOIN corruption_targets ct ON p.payment_id = ct.payment_id
    SET p.amount = 0.01;
    
    DROP TEMPORARY TABLE corruption_targets;
"

# 3. Select a control group (non-corrupted) to ensure safety
# These are payments that were NOT touched. We record their current amount.
mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT p.payment_id, p.amount
    FROM payment p
    WHERE p.amount > 0.99
    ORDER BY RAND()
    LIMIT 10;
" > /tmp/ground_truth_control.txt

CORRUPTED_COUNT=$(wc -l < /tmp/ground_truth_targets.txt)
echo "Corrupted $CORRUPTED_COUNT payment records to $0.01"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="