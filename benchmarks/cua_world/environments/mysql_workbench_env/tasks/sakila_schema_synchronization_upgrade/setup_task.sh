#!/bin/bash
# Setup script for sakila_schema_synchronization_upgrade task

echo "=== Setting up Sakila Schema Synchronization Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# 1. Reset 'sakila' to standard state (Production)
echo "Resetting production database 'sakila'..."
# Re-run the environment setup logic for sakila to ensure it's clean and populated
if [ -f "/tmp/sakila-db/sakila-schema.sql" ]; then
    mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-schema.sql 2>/dev/null
    mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-data.sql 2>/dev/null
else
    # Fallback if tmp is cleared, use the one in documents or download again
    wget -q "https://downloads.mysql.com/docs/sakila-db.zip" -O /tmp/sakila-db.zip
    unzip -o /tmp/sakila-db.zip -d /tmp/
    mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-schema.sql
    mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-data.sql
fi

# 2. Create 'sakila_next' (Development)
echo "Creating development database 'sakila_next'..."
mysql -u root -p'GymAnything#2024' -e "DROP DATABASE IF EXISTS sakila_next; CREATE DATABASE sakila_next;"

# Load standard schema into sakila_next (no data needed for dev schema structure)
mysql -u root -p'GymAnything#2024' sakila_next < /tmp/sakila-db/sakila-schema.sql

# 3. Apply 'New Features' to sakila_next
echo "Applying v2 changes to 'sakila_next'..."
mysql -u root -p'GymAnything#2024' sakila_next -e "
    -- Feature 1: Customer Loyalty
    ALTER TABLE customer ADD COLUMN loyalty_tier ENUM('Bronze','Silver','Gold') DEFAULT 'Bronze' AFTER email;
    
    -- Feature 2: Streaming Support
    ALTER TABLE film ADD COLUMN streaming_url VARCHAR(255) DEFAULT NULL;
    
    -- Feature 3: Payment Performance Index
    CREATE INDEX idx_payment_date_amount ON payment(payment_date, amount);
    
    -- Feature 4: Audit Logging
    CREATE TABLE rental_audit_log (
      audit_id INT AUTO_INCREMENT PRIMARY KEY,
      rental_id INT NOT NULL,
      action VARCHAR(50),
      old_return_date DATETIME,
      new_return_date DATETIME,
      changed_by VARCHAR(50),
      log_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
"

# 4. Grant permissions
mysql -u root -p'GymAnything#2024' -e "
    GRANT ALL PRIVILEGES ON sakila.* TO 'ga'@'localhost';
    GRANT ALL PRIVILEGES ON sakila_next.* TO 'ga'@'localhost';
    FLUSH PRIVILEGES;
"

# 5. Prepare export directory
mkdir -p /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/migration_v2.sql 2>/dev/null
chown -R ga:ga /home/ga/Documents

# 6. Ensure Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi
focus_workbench

# Record initial row counts for anti-gaming (data preservation check)
CUST_COUNT=$(sakila_query "SELECT COUNT(*) FROM customer")
FILM_COUNT=$(sakila_query "SELECT COUNT(*) FROM film")
echo "Initial Sakila counts - Customer: $CUST_COUNT, Film: $FILM_COUNT"
echo "$CUST_COUNT" > /tmp/initial_cust_count
echo "$FILM_COUNT" > /tmp/initial_film_count

take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="