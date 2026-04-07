#!/bin/bash
set -e
echo "=== Setting up task: Legacy CSV Roster Import ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create Directories
mkdir -p /home/ga/legacy_data
mkdir -p /home/ga/hl7_import
# Ensure ga user owns them so agent can access/write
chown -R ga:ga /home/ga/legacy_data
chown -R ga:ga /home/ga/hl7_import
chmod 777 /home/ga/hl7_import

# 2. Generate Realistic CSV Data
# Using a python script to generate a consistent CSV with known data for verification
cat > /tmp/generate_csv.py << 'EOF'
import csv
import random
import os

# Fixed seed for reproducibility
random.seed(42)

headers = ["PatientID", "FirstName", "LastName", "DOB", "Gender", "Address", "City", "State", "Zip"]

first_names = ["James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda", "William", "Elizabeth"]
last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez"]
cities = ["Springfield", "Rivertown", "Lakeside", "Hillcrest", "Mapleton"]
states = ["IL", "CA", "NY", "TX", "FL"]

records = []
for i in range(1, 21):
    pid = f"PAT{1000+i}"
    fname = random.choice(first_names)
    lname = random.choice(last_names)
    
    # Generate random date MM/DD/YYYY
    month = random.randint(1, 12)
    day = random.randint(1, 28)
    year = random.randint(1950, 2010)
    dob = f"{month}/{day}/{year}"
    
    gender = "Male" if random.random() > 0.5 else "Female"
    
    addr = f"{random.randint(100, 999)} {random.choice(['Oak', 'Maple', 'Main', 'Cedar'])} St"
    city = random.choice(cities)
    state = random.choice(states)
    zip_code = f"{random.randint(10000, 99999)}"
    
    records.append([pid, fname, lname, dob, gender, addr, city, state, zip_code])

output_path = '/home/ga/legacy_data/patient_roster.csv'
with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(headers)
    writer.writerows(records)

# Also save a ground truth JSON for the verifier to compare against later if needed
import json
with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(records, f)

print(f"Generated {len(records)} records at {output_path}")
EOF

python3 /tmp/generate_csv.py
chown ga:ga /home/ga/legacy_data/patient_roster.csv

# 3. Ensure NextGen Connect is running
echo "Waiting for NextGen Connect API..."
wait_for_api 60 || echo "Warning: API not ready yet"

# 4. Launch Firefox to Landing Page
if ! pgrep -f "firefox" > /dev/null; then
    echo "Launching Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Firefox"; then
            break
        fi
        sleep 1
    done
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Open a terminal for the agent
DISPLAY=:1 gnome-terminal --geometry=100x24+50+50 -- bash -c '
echo "============================================"
echo " Legacy Data Migration Task"
echo "============================================"
echo "Source File: /home/ga/legacy_data/patient_roster.csv"
echo "Output Dir : /home/ga/hl7_import/"
echo ""
echo "Goal: Convert CSV to HL7 ADT^A28"
echo "Transformations required:"
echo "  - DOB: MM/DD/YYYY -> YYYYMMDD"
echo "  - Gender: Male/Female -> M/F"
echo ""
echo "API Credentials: admin / admin"
echo "============================================"
exec bash
' 2>/dev/null &

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="