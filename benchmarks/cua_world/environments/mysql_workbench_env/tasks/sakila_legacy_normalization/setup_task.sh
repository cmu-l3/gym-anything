#!/bin/bash
# Setup script for sakila_legacy_normalization task
# Creates a "legacy" flat table by denormalizing the Sakila database

echo "=== Setting up Sakila Legacy Normalization Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions for utilities
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type start_workbench &>/dev/null; then
    start_workbench() { su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"; sleep 10; }
fi
if ! type is_workbench_running &>/dev/null; then
    is_workbench_running() { pgrep -f "mysql-workbench" > /dev/null 2>&1 && echo "true" || echo "false"; }
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

# Create legacy_data database and rental_flat table
echo "Generating legacy flat table..."
mysql -u root -p'GymAnything#2024' -e "DROP DATABASE IF EXISTS legacy_data;"
mysql -u root -p'GymAnything#2024' -e "CREATE DATABASE legacy_data;"

# Create the massive flat table query
# We join rental -> inventory -> film -> film_category -> category
# rental -> customer -> address -> city -> country
# rental -> staff -> store -> address -> city
# rental -> payment (left join)
mysql -u root -p'GymAnything#2024' legacy_data -e "
    CREATE TABLE rental_flat AS
    SELECT 
        r.rental_id,
        r.rental_date,
        r.return_date,
        c.first_name AS customer_first_name,
        c.last_name AS customer_last_name,
        c.email AS customer_email,
        a.address AS customer_address,
        ci.city AS customer_city,
        co.country AS customer_country,
        f.title AS film_title,
        f.release_year AS film_release_year,
        f.rental_rate AS film_rental_rate,
        f.length AS film_length_minutes,
        cat.name AS film_category,
        s.store_id,
        sa.address AS store_address,
        sci.city AS store_city,
        p.amount AS payment_amount,
        p.payment_date
    FROM sakila.rental r
    JOIN sakila.customer c ON r.customer_id = c.customer_id
    JOIN sakila.address a ON c.address_id = a.address_id
    JOIN sakila.city ci ON a.city_id = ci.city_id
    JOIN sakila.country co ON ci.country_id = co.country_id
    JOIN sakila.inventory i ON r.inventory_id = i.inventory_id
    JOIN sakila.film f ON i.film_id = f.film_id
    JOIN sakila.film_category fc ON f.film_id = fc.film_id
    JOIN sakila.category cat ON fc.category_id = cat.category_id
    JOIN sakila.store s ON i.store_id = s.store_id
    JOIN sakila.address sa ON s.address_id = sa.address_id
    JOIN sakila.city sci ON sa.city_id = sci.city_id
    LEFT JOIN sakila.payment p ON r.rental_id = p.rental_id;
" 2>/dev/null

# Clean up any existing target database from previous runs
mysql -u root -p'GymAnything#2024' -e "DROP DATABASE IF EXISTS rental_norm;"

# Clean up export directory
rm -f /home/ga/Documents/exports/normalized_customers.csv 2>/dev/null || true

# Grant privileges to ga user
mysql -u root -p'GymAnything#2024' -e "
    GRANT ALL PRIVILEGES ON legacy_data.* TO 'ga'@'localhost';
    GRANT ALL PRIVILEGES ON rental_norm.* TO 'ga'@'localhost';
    FLUSH PRIVILEGES;
" 2>/dev/null

# Verify data generation
ROW_COUNT=$(mysql -u root -p'GymAnything#2024' legacy_data -N -e "SELECT COUNT(*) FROM rental_flat;" 2>/dev/null)
echo "Generated legacy_data.rental_flat with $ROW_COUNT rows."

# Start Workbench if not running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
fi

# Focus Workbench
focus_workbench

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="