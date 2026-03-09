#!/bin/bash
set -e
echo "=== Setting up University Decision Mail Merge Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents directory exists and has correct permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Generate realistic CSV data
# Using Python to generate consistent synthetic data
echo "Generating applicant data..."
python3 << 'PYEOF'
import csv
import random

# Seed for reproducibility
random.seed(42)

first_names = ["James", "Maria", "Robert", "Patricia", "John", "Jennifer", "Michael", "Linda", "David", "Elizabeth", "William", "Barbara", "Richard", "Susan", "Joseph", "Jessica", "Thomas", "Sarah", "Charles", "Karen", "Christopher", "Nancy", "Daniel", "Lisa", "Matthew"]
last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson", "White", "Harris"]
cities = ["Springfield", "Austin", "Seattle", "Boston", "Chicago", "Denver", "Atlanta", "Portland", "Miami", "Detroit", "Phoenix", "Dallas", "Houston", "San Diego", "Nashville"]
states = ["IL", "TX", "WA", "MA", "IL", "CO", "GA", "OR", "FL", "MI", "AZ", "TX", "TX", "CA", "TN"]
programs = ["Computer Science", "Biology", "Psychology", "Mechanical Engineering", "Business Administration", "Data Science", "Nursing", "English Literature"]

records = []
for i in range(1, 26):
    fname = first_names[i-1]
    lname = last_names[i-1]
    address = f"{random.randint(100, 999)} {random.choice(['Maple', 'Oak', 'Pine', 'Cedar', 'Elm', 'Main', 'Washington'])} {random.choice(['St', 'Ave', 'Blvd', 'Ln', 'Dr'])}"
    city_idx = random.randint(0, len(cities)-1)
    
    # Logic: 60% Admit rate
    decision = "Admit" if random.random() < 0.6 else "Deny"
    
    record = {
        "ApplicantID": 1000 + i,
        "FirstName": fname,
        "LastName": lname,
        "Address": address,
        "City": cities[city_idx],
        "State": states[city_idx],
        "Zip": random.randint(10000, 99999),
        "Program": random.choice(programs),
        "Decision": decision
    }
    records.append(record)

csv_file = "/home/ga/Documents/applicants.csv"
with open(csv_file, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["ApplicantID", "FirstName", "LastName", "Address", "City", "State", "Zip", "Program", "Decision"])
    writer.writeheader()
    writer.writerows(records)

print(f"Generated {len(records)} records to {csv_file}")
PYEOF

# Set permissions for the CSV
chown ga:ga /home/ga/Documents/applicants.csv
chmod 666 /home/ga/Documents/applicants.csv

# Ensure LibreOffice is not running
pkill -f "soffice" || true
pkill -f "libreoffice" || true
sleep 1

# Start LibreOffice Writer with a blank document
echo "Starting LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore > /tmp/writer.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Writer" 60 || echo "WARNING: Writer window not found"

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any initial dialogs (Tip of the Day, etc)
sleep 2
safe_xdotool ga :1 key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="