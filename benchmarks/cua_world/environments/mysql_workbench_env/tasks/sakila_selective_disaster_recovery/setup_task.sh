#!/bin/bash
# Setup script for sakila_selective_disaster_recovery
# Simulates a data loss scenario with schema evolution

echo "=== Setting up Sakila Disaster Recovery Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not loaded
if ! type is_mysql_running &>/dev/null; then
    is_mysql_running() { mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null && echo "true" || echo "false"; }
fi
if ! type start_workbench &>/dev/null; then
    start_workbench() { su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"; sleep 10; }
fi

# 1. Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# 2. Reset Sakila to standard state
echo "Resetting Sakila database..."
mysql -u root -p'GymAnything#2024' -e "DROP DATABASE IF EXISTS sakila;" 2>/dev/null
# Re-load Sakila (assuming setup_mysql_workbench.sh has put scripts in /home/ga/Documents/sql_scripts or /tmp)
# We'll use the official source if available
if [ -f "/home/ga/Documents/sql_scripts/sakila-schema.sql" ]; then
    mysql -u root -p'GymAnything#2024' < "/home/ga/Documents/sql_scripts/sakila-schema.sql"
    mysql -u root -p'GymAnything#2024' < "/home/ga/Documents/sql_scripts/sakila-data.sql"
else
    # Try to download if missing (should be there from env setup)
    wget -qO- https://downloads.mysql.com/docs/sakila-db.tar.gz | tar xvz -C /tmp
    mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-schema.sql
    mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-data.sql
fi

# 3. Create the "Legacy" Backup
# We take a dump of the payment table BEFORE adding the new column
echo "Creating legacy backup..."
mysqldump -u root -p'GymAnything#2024' sakila payment > /home/ga/Documents/sakila_legacy_dump.sql

# 4. Evolve the Schema (Simulate Production changes)
# Add 'audit_tag' column and populate it
echo "Evolving production schema..."
mysql -u root -p'GymAnything#2024' sakila -e "
    ALTER TABLE payment ADD COLUMN audit_tag VARCHAR(20) DEFAULT 'original' AFTER last_update;
    UPDATE payment SET audit_tag = 'original';
    -- Mark some as verified to make it realistic
    UPDATE payment SET audit_tag = 'verified' WHERE payment_id % 5 = 0;
"

# 5. Simulate the Disaster (Delete records)
# Gap: May 25, 2005 to May 28, 2005
echo "Simulating data loss..."
mysql -u root -p'GymAnything#2024' sakila -e "
    DELETE FROM payment 
    WHERE payment_date >= '2005-05-25 00:00:00' 
      AND payment_date <= '2005-05-28 23:59:59';
"

# 6. Set permissions and cleanup
chown ga:ga /home/ga/Documents/sakila_legacy_dump.sql
# Clean previous exports
rm -f /home/ga/Documents/exports/restored_payments.csv 2>/dev/null

# 7. Start Workbench
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 5
fi

# Focus Workbench
DISPLAY=:1 wmctrl -a "MySQL Workbench" 2>/dev/null || true

# 8. Record Initial State for Verification
TOTAL_ROWS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM payment;")
echo "$TOTAL_ROWS" > /tmp/initial_row_count
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Current rows in payment: $TOTAL_ROWS (Expected ~15846)"
echo "Backup created at: /home/ga/Documents/sakila_legacy_dump.sql"