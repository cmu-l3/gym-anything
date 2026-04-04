#!/bin/bash
# Setup script for export_data task
# Records initial state before agent action

echo "=== Setting up Export Data Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure DBeaver is running
if [ "$(is_dbeaver_running)" = "false" ]; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver window
focus_dbeaver

# Create exports directory if it doesn't exist
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Record initial state - verify customer count
echo "Verifying database state..."
CUSTOMER_COUNT=$(chinook_query "SELECT COUNT(*) FROM customers;")
echo "Customers in database: $CUSTOMER_COUNT"
echo "$CUSTOMER_COUNT" > /tmp/expected_customer_count

# Record if any export file exists already
EXPORT_PATH="/home/ga/Documents/exports/customers_export.csv"
if [ -f "$EXPORT_PATH" ]; then
    INITIAL_SIZE=$(get_file_size "$EXPORT_PATH")
    echo "Existing export file size: $INITIAL_SIZE bytes"
    # Remove it to ensure we test fresh export
    rm -f "$EXPORT_PATH"
    echo "Removed existing export file"
fi
echo "0" > /tmp/initial_export_size

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="
