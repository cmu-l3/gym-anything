#!/bin/bash
# Setup script for world_schema_evolution_computed task

echo "=== Setting up World Schema Evolution Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Reset World database to ensure clean state (remove any previous schema changes)
echo "Resetting World database..."
# Check if original SQL exists, if not download it
if [ ! -f "/tmp/world.sql" ]; then
    wget -q "https://downloads.mysql.com/docs/world-db.zip" -O /tmp/world-db.zip
    unzip -o /tmp/world-db.zip -d /tmp/
    cp /tmp/world-db/world.sql /tmp/world.sql
fi

if [ -f "/tmp/world.sql" ]; then
    mysql -u root -p'GymAnything#2024' -e "DROP DATABASE IF EXISTS world; CREATE DATABASE world;"
    mysql -u root -p'GymAnything#2024' world < /tmp/world.sql
    echo "World database restored."
else
    echo "WARNING: Could not find world.sql, attempting to clean manually..."
    # Fallback cleanup
    mysql -u root -p'GymAnything#2024' world -e "
        ALTER TABLE country DROP COLUMN IF EXISTS gdp_per_capita;
        ALTER TABLE country DROP COLUMN IF EXISTS population_density;
        DROP TABLE IF EXISTS continent_stats;
        DROP FUNCTION IF EXISTS fn_classify_development;
        DROP VIEW IF EXISTS v_country_development_profile;
    " 2>/dev/null || true
fi

# Grant permissions to ga user
mysql -u root -p'GymAnything#2024' -e "GRANT ALL PRIVILEGES ON world.* TO 'ga'@'localhost'; FLUSH PRIVILEGES;"

# Ensure MySQL Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

# Focus the Workbench window
focus_workbench

# Clean up previous export
rm -f /home/ga/Documents/exports/country_development_profile.csv

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

# Create a clean results file
rm -f /tmp/schema_evolution_result.json

echo "=== Task setup complete ==="