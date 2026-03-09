#!/bin/bash
# Setup script for run_sql_query task

echo "=== Setting up Run SQL Query task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Verify Sakila database exists and has data
echo "Verifying Sakila database..."
FILM_COUNT=$(sakila_query "SELECT COUNT(*) FROM film WHERE rental_rate > 2.99")
echo "Films with rental_rate > 2.99: $FILM_COUNT"

# Record expected count for verification
echo "$FILM_COUNT" > /tmp/expected_film_count

# Ensure MySQL Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

# Focus the Workbench window
focus_workbench

# Clean up any previous export files
rm -f /home/ga/Documents/exports/expensive_films.csv 2>/dev/null || true
rm -f /home/ga/Documents/exports/expensive_films*.csv 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

# Clear any previous result files
rm -f /tmp/query_result.json 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Agent should now:"
echo "1. Connect to MySQL server (localhost, user: ga, password: password123)"
echo "2. Run query: SELECT title, rental_rate FROM film WHERE rental_rate > 2.99"
echo "3. Export results to /home/ga/Documents/exports/expensive_films.csv"
