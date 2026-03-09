#!/bin/bash
set -euo pipefail

echo "=== Setting up Purge Historical Records task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "purge_historical_records"

# Generate the legacy CSV file with Python to ensure correct format and dates
cat << EOF > /tmp/gen_csv.py
import csv
import random
from datetime import datetime, timedelta

# Define records: (First, Last, Company, Date_Str)
# Date format: MM/DD/YYYY usually works best for Windows apps imports
records = [
    ("Arthur", "Dent", "Galactic Imports", "05/15/2020"),      # DELETE
    ("Ford", "Prefect", "Guide Publications", "02/01/2024"),  # KEEP
    ("Zaphod", "Beeblebrox", "Government", "01/01/2019"),     # DELETE
    ("Tricia", "McMillan", "Science Inst", "06/15/2023"),     # KEEP
    ("Marvin", "Android", "Sirius Cybernetics", "12/31/2022"),# DELETE
    ("Slartibartfast", "Magrathea", "03/10/2025")             # KEEP
]

# Add some filler data
for i in range(10):
    year = random.choice([2019, 2020, 2021, 2022, 2023, 2024])
    date_obj = datetime(year, random.randint(1, 12), random.randint(1, 28))
    date_str = date_obj.strftime("%m/%d/%Y")
    records.append((f"Visitor{i}", f"Test{i}", "TestCorp", date_str))

header = ["First Name", "Last Name", "Company", "Visit Date"]
output_path = "/home/ga/Desktop/legacy_visitor_log.csv"

with open(output_path, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(header)
    for r in records:
        writer.writerow(r)

print(f"Created {output_path} with {len(records)} records")
EOF

python3 /tmp/gen_csv.py

# Ensure permissions
chown ga:ga /home/ga/Desktop/legacy_visitor_log.csv
chmod 644 /home/ga/Desktop/legacy_visitor_log.csv

# Ensure Documents folder exists for export
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Launch Lobby Track
launch_lobbytrack

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Legacy data created at /home/ga/Desktop/legacy_visitor_log.csv"