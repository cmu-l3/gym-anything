#!/bin/bash
# Setup script for sakila_inventory_shrinkage_audit task

echo "=== Setting up Sakila Inventory Shrinkage Audit Task ==="

source /workspace/scripts/task_utils.sh

# Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Ensure MySQL Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi
focus_workbench

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Create directories
mkdir -p /home/ga/Documents/imports
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents

# Clean up previous artifacts
echo "Cleaning up previous state..."
rm -f /home/ga/Documents/imports/store1_physical_count.csv
rm -f /home/ga/Documents/exports/shrinkage_report.csv
mysql -u root -p'GymAnything#2024' sakila -e "DROP TABLE IF EXISTS inventory_audit;" 2>/dev/null || true
mysql -u root -p'GymAnything#2024' sakila -e "DROP FUNCTION IF EXISTS fn_get_shrinkage_status;" 2>/dev/null || true
mysql -u root -p'GymAnything#2024' sakila -e "DROP VIEW IF EXISTS v_store1_shrinkage_report;" 2>/dev/null || true

# Generate Realistic Physical Count CSV
# We query the actual DB to get current system counts, then modify specific ones
# to create known ground-truth discrepancies.
echo "Generating physical count CSV..."

python3 -c "
import pymysql
import csv
import random

# Connect to DB
conn = pymysql.connect(host='localhost', user='root', password='GymAnything#2024', database='sakila')
cursor = conn.cursor()

# Get current system inventory for Store 1
cursor.execute('SELECT film_id, COUNT(*) as cnt FROM inventory WHERE store_id = 1 GROUP BY film_id ORDER BY film_id')
inventory = cursor.fetchall()

# Prepare CSV data with injected discrepancies
# Ground Truth:
# Film 1 (ACADEMY DINOSAUR): Make MISSING (Actual = System - 1)
# Film 2 (ACE GOLDFINGER): Make EXTRA (Actual = System + 1)
# Film 3: Match
# ... others match
# Film 10: Make MISSING (Actual = System - 1)

csv_data = []
ground_truth = {}

for film_id, system_count in inventory:
    actual_count = system_count
    
    # Inject discrepancies
    if film_id == 1:
        actual_count = max(0, system_count - 1)
        ground_truth[film_id] = {'type': 'MISSING', 'variance': 1}
    elif film_id == 2:
        actual_count = system_count + 1
        ground_truth[film_id] = {'type': 'EXTRA', 'variance': -1}
    elif film_id == 10:
        actual_count = max(0, system_count - 1)
        ground_truth[film_id] = {'type': 'MISSING', 'variance': 1}
    
    csv_data.append([film_id, actual_count])

# Write CSV
with open('/home/ga/Documents/imports/store1_physical_count.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['film_id', 'actual_count'])
    writer.writerows(csv_data)

# Save ground truth for verification later
import json
with open('/tmp/shrinkage_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)

conn.close()
"

chown ga:ga /home/ga/Documents/imports/store1_physical_count.csv

echo "Initial state setup complete."
echo "Ground truth saved to /tmp/shrinkage_ground_truth.json"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png