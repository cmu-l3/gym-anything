#!/bin/bash
# Setup script for sakila_stored_procedure_debugging task

echo "=== Setting up Sakila Stored Procedure Debugging Task ==="

source /workspace/scripts/task_utils.sh

# Define fallback functions if utils not present
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

# Clean up previous exports
rm -f /home/ga/Documents/exports/sales_by_category.csv 2>/dev/null || true
rm -f /home/ga/Documents/exports/dead_inventory.csv 2>/dev/null || true
rm -f /home/ga/Documents/exports/top_credit_customers.csv 2>/dev/null || true

echo "Resetting database state..."

# 1. Remove credit_score column if it exists (to break the 3rd proc)
mysql -u root -p'GymAnything#2024' sakila -e "
    SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='customer' AND COLUMN_NAME='credit_score');
    SET @sql := IF(@exist > 0, 'ALTER TABLE sakila.customer DROP COLUMN credit_score', 'SELECT \"Column already gone\"');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
" 2>/dev/null || true

# 2. Inject Broken Procedures
echo "Injecting broken stored procedures..."

mysql -u root -p'GymAnything#2024' sakila -e "
DROP PROCEDURE IF EXISTS sp_report_sales_by_category;
DROP PROCEDURE IF EXISTS sp_identify_dead_inventory;
DROP PROCEDURE IF EXISTS sp_calculate_customer_credit;
"

# Procedure 1: Broken GROUP BY (Error 1055)
# Using sql_mode=only_full_group_by is default in modern MySQL, so this will fail
mysql -u root -p'GymAnything#2024' sakila <<EOF
DELIMITER //
CREATE PROCEDURE sp_report_sales_by_category()
BEGIN
    SELECT c.name AS category_name, SUM(p.amount) as total_sales
    FROM category c
    JOIN film_category fc ON c.category_id = fc.category_id
    JOIN film f ON fc.film_id = f.film_id
    JOIN inventory i ON f.film_id = i.film_id
    JOIN rental r ON i.inventory_id = r.inventory_id
    JOIN payment p ON r.rental_id = p.rental_id
    GROUP BY c.category_id; -- Fails strict mode because c.name is not in GROUP BY
END //
DELIMITER ;
EOF

# Procedure 2: Logic Error (Inner Join instead of Left Join/Not Exists)
# Returns 0 rows because it looks for items in inventory that ARE in rental but where rental_date is NULL (impossible in this schema context usually)
# or simply logic is wrong for "dead inventory" (never rented).
# Correct logic: inventory LEFT JOIN rental ... WHERE rental_id IS NULL
mysql -u root -p'GymAnything#2024' sakila <<EOF
DELIMITER //
CREATE PROCEDURE sp_identify_dead_inventory()
BEGIN
    SELECT i.inventory_id, f.title
    FROM inventory i
    JOIN film f ON i.film_id = f.film_id
    JOIN rental r ON i.inventory_id = r.inventory_id -- INNER JOIN wrong for finding missing rentals
    WHERE r.rental_date IS NULL;
END //
DELIMITER ;
EOF

# Procedure 3: Missing Column Error
mysql -u root -p'GymAnything#2024' sakila <<EOF
DELIMITER //
CREATE PROCEDURE sp_calculate_customer_credit()
BEGIN
    UPDATE customer c
    JOIN (SELECT customer_id, COUNT(*) as rental_count FROM rental GROUP BY customer_id) r 
      ON c.customer_id = r.customer_id
    SET c.credit_score = r.rental_count * 10; -- Column credit_score does not exist yet
END //
DELIMITER ;
EOF

# Ensure MySQL Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

focus_workbench
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Broken procedures injected. Customer column dropped."