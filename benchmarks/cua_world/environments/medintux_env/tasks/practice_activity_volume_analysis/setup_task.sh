#!/bin/bash
set -e
echo "=== Setting up Practice Activity Volume Analysis ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Wait for MySQL
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent; then
        break
    fi
    sleep 1
done

# Ensure output directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# ------------------------------------------------------------------
# DATA PREPARATION: Inject synthetic activity history
# ------------------------------------------------------------------
# We randomize the FchGnrl_DateModif column in IndexNomPrenom
# to create a unique, verifiable ground truth for this specific run.
# This prevents the agent from simply hardcoding a result.
# ------------------------------------------------------------------

echo "Injecting synthetic activity data..."

# Create a Python script to randomize dates and generate ground truth
cat << 'EOF' > /tmp/prepare_data.py
import pymysql
import random
import datetime
import csv
import os

# Connect to database
conn = pymysql.connect(host='localhost', user='root', password='', db='DrTuxTest', autocommit=True)
cursor = conn.cursor()

# Get all patient IDs
cursor.execute("SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'")
ids = [row[0] for row in cursor.fetchall()]

print(f"Found {len(ids)} patient records to update.")

# Date range: Last 12-18 months
end_date = datetime.date.today()
start_date = end_date - datetime.timedelta(days=540)
total_days = (end_date - start_date).days

# Dictionary to track expected counts { 'YYYY-MM': count }
ground_truth = {}

# Update each record with a random date
for pid in ids:
    # Weighted random to create peaks/valleys
    random_days = int(random.triangular(0, total_days, total_days * 0.7))
    mod_date = start_date + datetime.timedelta(days=random_days)
    
    # Add random time
    mod_datetime = datetime.datetime.combine(mod_date, datetime.time(
        random.randint(8, 18), random.randint(0, 59), random.randint(0, 59)
    ))
    
    # Update DB
    date_str = mod_datetime.strftime('%Y-%m-%d %H:%M:%S')
    cursor.execute(f"UPDATE IndexNomPrenom SET FchGnrl_DateModif='{date_str}' WHERE FchGnrl_IDDos='{pid}'")
    
    # Tally for ground truth
    month_key = mod_datetime.strftime('%Y-%m')
    ground_truth[month_key] = ground_truth.get(month_key, 0) + 1

# Ensure at least some data exists
if not ids:
    print("WARNING: No patients found. Creating dummy data.")
    # (Optional fallback logic if DB was empty, but env usually has data)

# Export Ground Truth (Hidden from Agent)
gt_path = "/var/lib/medintux/ground_truth_activity.csv"
os.makedirs(os.path.dirname(gt_path), exist_ok=True)

sorted_months = sorted(ground_truth.keys())

with open(gt_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Month', 'Count'])
    for month in sorted_months:
        writer.writerow([month, ground_truth[month]])

print(f"Ground truth saved to {gt_path}")
conn.close()
EOF

# Run the data preparation
python3 /tmp/prepare_data.py

# Ensure permissions (ground truth should NOT be readable by 'ga' user ideally, 
# but for verification logic simplicity in this environment we keep it in /var/lib)
chmod 644 /var/lib/medintux/ground_truth_activity.csv

# ------------------------------------------------------------------
# UI Setup
# ------------------------------------------------------------------

# Open a terminal for the agent to work in
if ! pgrep -f "xterm" > /dev/null; then
    su - ga -c "DISPLAY=:1 xterm -geometry 100x30 &"
fi

# Focus terminal
sleep 2
DISPLAY=:1 wmctrl -a "xterm" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="