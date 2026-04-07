#!/bin/bash
set -e
echo "=== Setting up Create Address Parsing View task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
if ! pgrep -x "mysqld" > /dev/null; then
    echo "Starting MySQL..."
    service mysql start
    sleep 5
fi

# Clean up previous artifacts
echo "Cleaning up previous state..."
mysql -u root -e "DROP VIEW IF EXISTS DrTuxTest.vue_adresse_parsed;" 2>/dev/null || true
rm -f /home/ga/Documents/parsed_addresses.csv

# Ensure target database exists
if ! mysql -u root -e "USE DrTuxTest;" 2>/dev/null; then
    echo "ERROR: DrTuxTest database not found!"
    exit 1
fi

# Ensure there is some data to work with (if empty, populate minimal data)
ROW_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat" 2>/dev/null || echo 0)
if [ "$ROW_COUNT" -lt 5 ]; then
    echo "Populating sample data..."
    # Insert a sample patient if needed (simplified schema)
    # This relies on the environment having the schema already, which it should.
    # We won't reconstruct the whole DB here, just assuming the env is healthy.
    echo "Warning: Low data count ($ROW_COUNT rows). Assuming environment defaults."
fi

# Maximize MedinTux Manager if it's running (not strictly required for this SQL task, but good practice)
DISPLAY=:1 wmctrl -r "Manager" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="