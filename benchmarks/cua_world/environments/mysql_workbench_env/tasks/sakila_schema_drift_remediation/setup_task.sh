#!/bin/bash
# Setup script for sakila_schema_drift_remediation
# Creates a "Gold" standard DB and a "Prod" DB with specific schema drifts and live data.

echo "=== Setting up Sakila Schema Drift Remediation Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# 2. Setup sakila_gold (The Reference)
echo "Setting up sakila_gold (Reference)..."
mysql -u root -p'GymAnything#2024' -e "DROP DATABASE IF EXISTS sakila_gold;" 2>/dev/null
# We assume standard sakila is available or can be loaded. 
# Using the setup logic from env setup:
if [ -f "/home/ga/Documents/sql_scripts/sakila-schema.sql" ]; then
    mysql -u root -p'GymAnything#2024' -e "CREATE DATABASE sakila_gold;"
    mysql -u root -p'GymAnything#2024' sakila_gold < /home/ga/Documents/sql_scripts/sakila-schema.sql
    mysql -u root -p'GymAnything#2024' sakila_gold < /home/ga/Documents/sql_scripts/sakila-data.sql
else
    # Fallback: clone from existing 'sakila' if available
    echo "Cloning sakila_gold from sakila..."
    mysqldump -u root -p'GymAnything#2024' --databases sakila > /tmp/sakila_dump.sql
    sed 's/`sakila`/`sakila_gold`/g' /tmp/sakila_dump.sql | mysql -u root -p'GymAnything#2024'
fi

# 3. Setup sakila_prod (The Drifted Environment)
echo "Setting up sakila_prod (Target)..."
mysql -u root -p'GymAnything#2024' -e "DROP DATABASE IF EXISTS sakila_prod;"
# Clone gold to prod initially
mysqldump -u root -p'GymAnything#2024' --databases sakila_gold > /tmp/gold_dump.sql
sed 's/`sakila_gold`/`sakila_prod`/g' /tmp/gold_dump.sql | mysql -u root -p'GymAnything#2024'

# 4. Apply Schema Drifts to sakila_prod
echo "Applying unauthorized schema changes to sakila_prod..."

# Drift A: Modify column type
# sakila_gold: customer.last_name is VARCHAR(45)
# sakila_prod: customer.last_name -> VARCHAR(100)
mysql -u root -p'GymAnything#2024' sakila_prod -e "ALTER TABLE customer MODIFY COLUMN last_name VARCHAR(100) NOT NULL;"

# Drift B: Drop an index
# sakila_gold: address has idx_fk_city_id
mysql -u root -p'GymAnything#2024' sakila_prod -e "ALTER TABLE address DROP INDEX idx_fk_city_id;"

# Drift C: Add unauthorized column
# sakila_prod: store gets 'internal_notes'
mysql -u root -p'GymAnything#2024' sakila_prod -e "ALTER TABLE store ADD COLUMN internal_notes TEXT AFTER last_update;"

# Drift D: Break a view
# sakila_prod: customer_list view missing 'country'
# Recreating view without the country column
mysql -u root -p'GymAnything#2024' sakila_prod -e "
CREATE OR REPLACE VIEW customer_list AS
SELECT 
  cu.customer_id AS ID, 
  CONCAT(cu.first_name, _utf8' ', cu.last_name) AS name, 
  a.address AS address, 
  a.postal_code AS 'zip code',
  a.phone AS phone, 
  city.city AS city, 
  IF(cu.active, _utf8'active', _utf8'') AS notes, 
  cu.store_id AS SID 
FROM customer AS cu 
JOIN address AS a ON cu.address_id = a.address_id 
JOIN city ON a.city_id = city.city_id;
"

# 5. Insert "Live Data" (Tracer)
# This data exists ONLY in prod. If the agent drops/recreates prod from gold, this data will vanish.
echo "Inserting live transaction data..."
mysql -u root -p'GymAnything#2024' sakila_prod -e "
    INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id) 
    VALUES (NOW(), 1, 1, NULL, 1);
    SET @new_id = LAST_INSERT_ID();
    INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
    VALUES (1, 1, @new_id, 99.99, NOW());
"

# Get the ID of the tracer record for verification
TRACER_ID=$(mysql -u root -p'GymAnything#2024' sakila_prod -N -e "SELECT MAX(rental_id) FROM rental WHERE amount IS NULL" 2>/dev/null || echo "0")
echo "$TRACER_ID" > /tmp/tracer_rental_id.txt

# 6. Grant permissions
mysql -u root -p'GymAnything#2024' -e "
    GRANT ALL PRIVILEGES ON sakila_gold.* TO 'ga'@'localhost';
    GRANT ALL PRIVILEGES ON sakila_prod.* TO 'ga'@'localhost';
    FLUSH PRIVILEGES;
"

# 7. Start Workbench
if [ "$(is_workbench_running)" = "false" ]; then
    start_workbench
    sleep 10
fi
focus_workbench

# Remove previous result
rm -f /home/ga/Documents/sql_scripts/revert_drift.sql

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Drifted environment 'sakila_prod' created."