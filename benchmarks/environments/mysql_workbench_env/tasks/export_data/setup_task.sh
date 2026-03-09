#!/bin/bash
# Setup script for export_data task

echo "=== Setting up Export Data task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Verify World database exists and has data
echo "Verifying World database..."
CITY_COUNT=$(world_query "SELECT COUNT(*) FROM city WHERE CountryCode = 'JPN'")
echo "Cities in Japan (CountryCode='JPN'): $CITY_COUNT"

# Record expected count for verification
echo "$CITY_COUNT" > /tmp/expected_city_count

# Show sample data
echo ""
echo "Sample Japanese cities:"
world_query "SELECT ID, Name, District, Population FROM city WHERE CountryCode = 'JPN' LIMIT 5"

# Ensure MySQL Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

# Focus the Workbench window
focus_workbench

# Clean up any previous export files
rm -f /home/ga/Documents/exports/japan_cities.csv 2>/dev/null || true
rm -f /home/ga/Documents/exports/japan_cities*.csv 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

# Clear any previous result files
rm -f /tmp/export_result.json 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Agent should now:"
echo "1. Connect to MySQL server (localhost, user: ga, password: password123)"
echo "2. Select the 'world' database"
echo "3. Run query: SELECT * FROM city WHERE CountryCode = 'JPN'"
echo "4. Export results to /home/ga/Documents/exports/japan_cities.csv"
